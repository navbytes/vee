"""Drift guard: every example's build() output must match its committed golden
fixture. The fixtures are byte-identical to the TypeScript SDK's, so this keeps
the Python SDK, the TS SDK, the shared fixtures, and the Swift parser in
lockstep.

Run with: python3 -m unittest discover -s test
"""

import importlib.util
import os
import unittest

_HERE = os.path.dirname(__file__)
_EXAMPLES = os.path.join(_HERE, "..", "examples")
_FIXTURES = os.path.join(_HERE, "..", "fixtures")


def _load(path: str):
    spec = importlib.util.spec_from_file_location("example", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DriftTests(unittest.TestCase):
    def test_fixtures_up_to_date(self) -> None:
        examples = sorted(f for f in os.listdir(_EXAMPLES) if f.endswith(".py"))
        self.assertTrue(examples, "expected at least one example plugin")
        for file in examples:
            with self.subTest(example=file):
                module = _load(os.path.join(_EXAMPLES, file))
                self.assertTrue(
                    hasattr(module, "build"), f"{file} must define build()"
                )
                output = module.build()
                fixture = os.path.join(_FIXTURES, file[:-3] + ".txt")
                with open(fixture, encoding="utf-8") as handle:
                    expected = handle.read().rstrip("\n")
                self.assertEqual(
                    output,
                    expected,
                    f"{file} output drifted from fixtures/{file[:-3]}.txt. "
                    f"Regenerate with: python3 examples/{file} > "
                    f"fixtures/{file[:-3]}.txt",
                )


if __name__ == "__main__":
    unittest.main()
