# PostgreSQL 17: 正規化テーブルでの複数テーブル横断検索

## 実行環境

- PostgreSQL 17
- Docker環境

## テーブル構成

典型的な図書館システムの正規化されたテーブル構造：

```sql
-- 出版社テーブル
CREATE TABLE publishers (
    publisher_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- 著者テーブル
CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- 書籍テーブル
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    publisher_id INT REFERENCES publishers(publisher_id)
);

-- 書籍-著者の中間テーブル（多対多）
CREATE TABLE book_authors (
    book_id INT REFERENCES books(book_id),
    author_id INT REFERENCES authors(author_id),
    PRIMARY KEY (book_id, author_id)
);
```

### リレーションシップ

```
publishers (1) ─────< (N) books
authors (N) ─────< book_authors >───── (N) books
```

### データ件数

| テーブル | 件数 | 「夏目」マッチ |
|---------|------|---------------|
| publishers | 1,000 | 100件（10%） |
| authors | 5,000 | 50件（1%） |
| books | 100,000 | 500件（0.5%） |
| book_authors | 100,000 | - |

### インデックス

```sql
CREATE INDEX idx_publishers_name ON publishers(name);
CREATE INDEX idx_authors_name ON authors(name);
CREATE INDEX idx_books_title ON books(title);
CREATE INDEX idx_books_publisher_id ON books(publisher_id);
CREATE INDEX idx_book_authors_book_id ON book_authors(book_id);
CREATE INDEX idx_book_authors_author_id ON book_authors(author_id);
```

## 比較結果

| パターン | 実行時間 | 高速化率 |
|---------|---------|---------|
| OR条件 + DISTINCT | 71.2 ms | - |
| UNION | 28.9 ms | 2.5倍 |
| **UNION ALL + DISTINCT** | **20.1 ms** | **3.5倍** |

すべて等価な結果（11,500行）を返す。

## 各パターンのSQL

### パターン1: OR条件 + DISTINCT

```sql
SELECT DISTINCT b.book_id, b.title
FROM books b
LEFT JOIN book_authors ba ON b.book_id = ba.book_id
LEFT JOIN authors a ON ba.author_id = a.author_id
LEFT JOIN publishers p ON b.publisher_id = p.publisher_id
WHERE
  a.name LIKE '%夏目%' OR
  b.title LIKE '%夏目%' OR
  p.name LIKE '%夏目%';
```

**実行時間: 71.2 ms**

**問題点:**
- すべてのテーブルをLEFT JOINする必要がある
- 100,000行を処理してから88,500行をフィルタで除外
- 結合後に重複除去（HashAggregate）
- Sequential Scanのみ

### パターン2: UNION

```sql
SELECT b.book_id, b.title
FROM books b
JOIN book_authors ba ON b.book_id = ba.book_id
JOIN authors a ON ba.author_id = a.author_id
WHERE a.name LIKE '%夏目%'

UNION

SELECT b.book_id, b.title
FROM books b
WHERE b.title LIKE '%夏目%'

UNION

SELECT b.book_id, b.title
FROM books b
JOIN publishers p ON b.publisher_id = p.publisher_id
WHERE p.name LIKE '%夏目%';
```

**実行時間: 28.9 ms**

**改善点:**
- 各クエリが必要なテーブルだけをJOIN
- 各UNION操作で重複除去
- OR条件より2.5倍高速

### パターン3: UNION ALL + DISTINCT（最速）

```sql
SELECT DISTINCT * FROM (
  SELECT b.book_id, b.title
  FROM books b
  JOIN book_authors ba ON b.book_id = ba.book_id
  JOIN authors a ON ba.author_id = a.author_id
  WHERE a.name LIKE '%夏目%'

  UNION ALL

  SELECT b.book_id, b.title
  FROM books b
  WHERE b.title LIKE '%夏目%'

  UNION ALL

  SELECT b.book_id, b.title
  FROM books b
  JOIN publishers p ON b.publisher_id = p.publisher_id
  WHERE p.name LIKE '%夏目%'
) sub;
```

**実行時間: 20.1 ms**

**最適化のポイント:**
- 並列実行（Parallel Append、2ワーカー）が発動
- すべて結合してから最後に1回だけ重複除去
- 各サブクエリが独立して最適化される
  - 著者検索: Nested Loop + Index Scan（1,000行）
  - タイトル検索: Sequential Scan（500行）
  - 出版社検索: Hash Join（10,000行）

## なぜUNION ALL + DISTINCTが最速なのか

### 1. 処理する行数の違い

| パターン | 処理行数 |
|---------|---------|
| OR条件 | 100,000行（全体）→ フィルタで88,500行除外 |
| UNION系 | 11,500行（絞り込み後のみ） |

### 2. JOIN戦略の違い

**OR条件:**
- すべてのテーブルをLEFT JOIN
- 著者だけで検索する場合も出版社テーブルまでJOIN（無駄）

**UNION系:**
- 各クエリが必要なテーブルだけをJOIN
- 著者検索は著者テーブルだけ、出版社検索は出版社テーブルだけ

### 3. 重複除去のタイミング

**UNION:**
- 各UNION操作ごとに重複チェック（複数回）

**UNION ALL + DISTINCT:**
- 最後に1回だけ重複除去（効率的）
- 並列処理（Parallel Append）と組み合わせ可能

## 実行計画の詳細

### パターン1: OR条件 + DISTINCT

```
HashAggregate (actual time=69.8..70.6ms rows=11500)
  -> Hash Left Join (著者)
       Filter: (著者 OR タイトル OR 出版社) にマッチ
       Rows Removed by Filter: 88500  ← 88%を除外
       -> Hash Left Join (出版社)
            -> Hash Right Join (書籍-著者)
                 -> Seq Scan on book_authors (100,000行)
                 -> Seq Scan on books (100,000行)
            -> Seq Scan on publishers (1,000行)
       -> Seq Scan on authors (5,000行)

Buffers: shared hit=1119
Execution Time: 71.2 ms
```

**特徴:**
- すべてSequential Scan
- 100,000行を処理してから88,500行を除外
- 最後にHashAggregateで重複除去

### パターン2: UNION

```
HashAggregate (actual time=27.5..28.3ms rows=11500)
  -> Append (UNION処理)
       -> Nested Loop (著者検索: 1,000行)
            -> Seq Scan on authors (50件ヒット)
            -> Bitmap Index Scan on book_authors
            -> Index Scan on books
       -> Seq Scan on books (タイトル検索: 500行)
       -> Hash Join (出版社検索: 10,000行)
            -> Seq Scan on books
            -> Hash of publishers (100件ヒット)

Buffers: shared hit=5421
Execution Time: 28.9 ms
```

**特徴:**
- 各クエリが独立して最適化
- Nested Loop + Index Scanを活用
- 最後にHashAggregateで重複除去

### パターン3: UNION ALL + DISTINCT（最速）

```
HashAggregate (actual time=18.8..19.6ms rows=11500)
  -> Gather (並列実行)
       Workers Planned: 2
       Workers Launched: 2
       -> HashAggregate (各ワーカー)
            -> Parallel Append
                 -> Hash Join (出版社: 10,000行)
                 -> Seq Scan (タイトル: 500行)
                 -> Nested Loop (著者: 1,000行)
                      -> Seq Scan on authors (50件)
                      -> Bitmap Index Scan on book_authors
                      -> Index Scan on books

Buffers: shared hit=5439
Execution Time: 20.1 ms
```

**特徴:**
- **並列実行（Parallel Append）が発動**
- 2ワーカーで並列処理
- 各サブクエリが独立して最適化
- 最後に1回だけ重複除去

## 結論

### このテストケースでの結果

- OR条件: 71.2 ms
- UNION: 28.9 ms
- UNION ALL + DISTINCT: 20.1 ms

このデータ・クエリでは、UNION ALL + DISTINCT が最速だった。

### UNION ALL + DISTINCT が有効な条件

以下の条件を**すべて**満たす場合に有効：

1. **正規化されたテーブル構造**
   - 複数テーブルをJOINする必要がある
   - OR条件では不要なテーブルまでJOINが必要になる

2. **各検索条件の選択性が高い**
   - 各条件が少数の行を返す（今回: 1,000 + 500 + 10,000 = 11,500行）
   - OR条件では大量の行を処理してフィルタリング（今回: 100,000行 → 88,500行除外）

3. **適切なインデックスが存在**
   - 各テーブルに検索対象カラムのインデックス
   - JOIN条件にもインデックス

4. **並列実行が可能**
   - PostgreSQL 17ではParallel Appendが発動しやすい

### 必ずしも速くなるとは限らない

以下の場合、OR条件の方が速い可能性：

- 選択性が低い（大量の行を返す）
- インデックスがない
- テーブルが小さい
- 検索条件が1つのテーブルに集中している

### 推奨アプローチ

1. まずOR条件で実装
2. パフォーマンス問題が発生したら
3. EXPLAIN ANALYZEで両方を比較
4. データの特性に合わせて選択

**安易に「UNION ALL + DISTINCTは速い」と判断せず、実測で確認すべき。**
