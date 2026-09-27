-- Inspect keywords, names, strings, numbers and operators.
WITH items AS (
  SELECT 4 AS count, 'Matrix' AS name
)
SELECT name, count + 2 AS total
FROM items
WHERE count > 0 AND name IS NOT NULL
ORDER BY total DESC;
