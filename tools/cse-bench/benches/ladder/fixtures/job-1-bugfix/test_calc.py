"""test_calc.py — acceptance tests for ladder job-1-bugfix (TASK-125 / W-3).

stdlib `unittest`, deliberately NOT pytest: this machine's default `python3`
(3.14, /opt/homebrew) has no pytest importable (verified live while building
this fixture — `python3 -m pytest` fails with "No module named pytest"), and
a bare-config job must not assume any tooling beyond what a fresh `python3`
already provides. `python3 test_calc.py` exits 0 on all-pass, non-zero
otherwise — the mechanical O-1 t_working check for this job.

The job brief tells the model NOT to modify this file.
"""
import unittest

from calc import add, average, subtract


class CalcTests(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)
        self.assertEqual(add(-1, 1), 0)

    def test_subtract(self):
        self.assertEqual(subtract(5, 2), 3)
        self.assertEqual(subtract(2, 5), -3)

    def test_average(self):
        self.assertEqual(average([2, 4, 6]), 4)
        self.assertEqual(average([10]), 10)
        self.assertEqual(average([1, 2, 3, 4]), 2.5)


if __name__ == "__main__":
    unittest.main()
