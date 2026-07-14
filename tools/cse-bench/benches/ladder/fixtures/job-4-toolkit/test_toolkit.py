"""test_toolkit.py — mechanical O-1 t_working acceptance test for
job-4-toolkit (job pack v2, framework-discriminating job). Stdlib
unittest, not pytest (this machine's default python3 has no pytest
importable — same constraint job-1-bugfix's test_calc.py already states).

PROTECTED per job_pack.py — the model must not modify this file. 6
independent functions, each with its own small test class (17 assertions
total): t_working requires ALL of them to pass, not a partial score — the
completeness-across-parts acceptance criterion this job exists to test
(see job_pack.py's JOBS docstring / the ladder README's job-pack-v2
section for why: a task big enough that decomposition matters, where a
framework's delegation/checklist machinery should show up as fewer
dropped parts under one shared token/turn budget, not as smarter code for
any single part).

Usage: python3 test_toolkit.py  (run FROM the job's own workdir — imports
toolkit.py via a relative/local import, same convention as job-1-bugfix's
test_calc.py).
"""
import unittest

from toolkit import (
    caesar_cipher,
    flatten,
    is_prime,
    most_common_word,
    reverse_words,
    run_length_encode,
)


class TestIsPrime(unittest.TestCase):
    def test_small(self):
        self.assertTrue(is_prime(2))
        self.assertFalse(is_prime(1))
        self.assertFalse(is_prime(0))
        self.assertFalse(is_prime(-7))

    def test_larger(self):
        self.assertTrue(is_prime(97))
        self.assertFalse(is_prime(100))


class TestReverseWords(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(reverse_words("the sky is blue"), "blue is sky the")

    def test_whitespace_collapse(self):
        self.assertEqual(reverse_words("  hello   world  "), "world hello")

    def test_edge_cases(self):
        self.assertEqual(reverse_words(""), "")
        self.assertEqual(reverse_words("single"), "single")


class TestFlatten(unittest.TestCase):
    def test_nested(self):
        self.assertEqual(flatten([1, [2, 3], [4, [5, 6]]]), [1, 2, 3, 4, 5, 6])

    def test_deep_nesting(self):
        self.assertEqual(flatten([[1, [2, [3, [4]]]]]), [1, 2, 3, 4])

    def test_edge_cases(self):
        self.assertEqual(flatten([]), [])
        self.assertEqual(flatten([1, 2, 3]), [1, 2, 3])


class TestRunLengthEncode(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(run_length_encode("aaabbc"), "a3b2c1")
        self.assertEqual(run_length_encode("aabbbba"), "a2b4a1")

    def test_edge_cases(self):
        self.assertEqual(run_length_encode(""), "")
        self.assertEqual(run_length_encode("abc"), "a1b1c1")


class TestMostCommonWord(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(most_common_word("The cat sat on the mat. The cat ran."), "the")
        self.assertEqual(most_common_word("apple Apple banana"), "apple")

    def test_tie_break_alphabetical(self):
        self.assertEqual(most_common_word("dog cat bird"), "bird")

    def test_single_word(self):
        self.assertEqual(most_common_word("one"), "one")


class TestCaesarCipher(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(caesar_cipher("abcXYZ", 3), "defABC")
        self.assertEqual(caesar_cipher("Hello, World!", 1), "Ifmmp, Xpsme!")

    def test_wraparound(self):
        self.assertEqual(caesar_cipher("xyz", 3), "abc")

    def test_negative_shift(self):
        self.assertEqual(caesar_cipher("abc", -1), "zab")

    def test_mixed_content(self):
        self.assertEqual(caesar_cipher("Test123!", 5), "Yjxy123!")


if __name__ == "__main__":
    unittest.main()
