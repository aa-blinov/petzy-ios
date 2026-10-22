#!/usr/bin/env python3
"""Отчёт о качестве кода по данным SwiftLint.

Читает JSON от `swiftlint lint --config .swiftlint-metrics.yml`. В том конфиге
пороги опущены до нуля: иначе в отчёт попадут одни нарушители, и средняя
посчитается по выжившим.

Отчёт ничего не решает: это замер. Проверка — `make lint-strict`.
"""

import collections
import json
import re
import statistics
import sys

# Где SwiftLint кладёт величину в текст сообщения. Форматы у правил разные, и
# угадывать их регуляркой «на всё» значит однажды тихо получить нули.
PATTERNS = {
    "cyclomatic_complexity": r"complexity is (\d+)",
    "function_body_length": r"currently spans (\d+) lines",
    "type_body_length": r"currently spans (\d+) lines",
    "file_length": r"currently contains (\d+)",
    "function_parameter_count": r"currently has (\d+)",
}


def measurements(data, rule):
    """Все величины правила: (значение, файл, строка)."""
    for item in data:
        if item["rule_id"] != rule:
            continue
        match = re.search(PATTERNS[rule], item["reason"])
        if match:
            yield int(match.group(1)), item["file"], item["line"]


def relative(path):
    marker = "/petzy-ios/"
    return path.split(marker)[-1] if marker in path else path


def worst(rows, unit, limit=5):
    """Пять худших мест: имя файла и строка, где это найдено."""
    for value, path, line in sorted(rows, reverse=True)[:limit]:
        print(f"  {value:5d}{unit}  {relative(path)}:{line}")


def main():
    data = json.load(sys.stdin)

    complexity = list(measurements(data, "cyclomatic_complexity"))
    values = [value for value, _, _ in complexity]
    if not values:
        sys.exit("SwiftLint не вернул сложность: проверьте .swiftlint-metrics.yml")

    print("# Качество кода\n")
    print(f"Функций и замыканий: {len(values)}")
    print(f"Сложность: средняя {statistics.mean(values):.2f}, "
          f"медиана {statistics.median(values):g}, максимум {max(values)}")
    histogram = collections.Counter(values)
    print("Распределение: " + ", ".join(
        f"{level} — {count}" for level, count in sorted(histogram.items())
    ))
    for threshold in (8, 12, 15):
        print(f"Сложнее {threshold}: {sum(1 for value in values if value > threshold)}")

    print("\nСамые сложные:")
    worst([row for row in complexity if row[0] > 3], "")

    for title, rule, unit in (
        ("Самые длинные функции", "function_body_length", " стр."),
        ("Самые длинные типы", "type_body_length", " стр."),
        ("Самые длинные файлы", "file_length", " стр."),
        ("Больше всего параметров", "function_parameter_count", ""),
    ):
        rows = list(measurements(data, rule))
        if not rows:
            continue
        lengths = [value for value, _, _ in rows]
        print(f"\n{title}: n={len(rows)}, медиана {statistics.median(lengths):g}{unit}, "
              f"максимум {max(lengths)}{unit}")
        worst(rows, unit)


if __name__ == "__main__":
    main()
