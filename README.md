# PostgreSQL 17: OR vs UNION パフォーマンス比較

正規化されたテーブル構造で、複数テーブルを横断検索する際のパフォーマンス比較。

## セットアップ

```bash
docker-compose up -d
```

## データ確認

```bash
docker exec -it postgres17-library psql -U library -d library_db
```

```sql
SELECT
  (SELECT COUNT(*) FROM publishers) as publishers,
  (SELECT COUNT(*) FROM authors) as authors,
  (SELECT COUNT(*) FROM books) as books,
  (SELECT COUNT(*) FROM book_authors) as book_authors;
```

## 比較結果

| パターン | 実行時間 | 高速化率 |
|---------|---------|---------|
| OR条件 + DISTINCT | 71.2 ms | - |
| UNION | 28.9 ms | 2.5倍 |
| **UNION ALL + DISTINCT** | **20.1 ms** | **3.5倍** |

詳細は [results.md](results.md) を参照。

## 実行計画

- `explain_or_distinct.txt` - OR条件 + DISTINCT
- `explain_union.txt` - UNION
- `explain_union_all_distinct.txt` - UNION ALL + DISTINCT

## クリーンアップ

```bash
docker-compose down -v
```
