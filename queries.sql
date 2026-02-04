-- パターン1: OR条件 + DISTINCT
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT b.book_id, b.title
FROM books b
INNER JOIN book_authors ba ON b.book_id = ba.book_id
INNER JOIN authors a ON ba.author_id = a.author_id
INNER JOIN publishers p ON b.publisher_id = p.publisher_id
WHERE
  a.name LIKE '%夏目%' OR
  b.title LIKE '%夏目%' OR
  p.name LIKE '%夏目%';

-- パターン2: UNION
EXPLAIN (ANALYZE, BUFFERS)
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

-- パターン3: UNION ALL + DISTINCT
EXPLAIN (ANALYZE, BUFFERS)
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
