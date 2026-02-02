INSERT INTO publishers (name)
SELECT
    CASE WHEN i % 10 = 0 THEN '夏目出版_' || i ELSE 'Publisher_' || i END
FROM generate_series(1, 1000) AS i;

INSERT INTO authors (name)
SELECT
    CASE WHEN i % 100 = 0 THEN '夏目漱石_' || i ELSE 'Author_' || i END
FROM generate_series(1, 5000) AS i;

INSERT INTO books (title, publisher_id)
SELECT
    CASE WHEN i % 200 = 0 THEN '夏目全集_' || i ELSE 'Book_' || i END,
    (i % 1000) + 1
FROM generate_series(1, 100000) AS i;

INSERT INTO book_authors (book_id, author_id)
SELECT book_id, ((book_id * 7) % 5000) + 1 FROM books;

ANALYZE;
