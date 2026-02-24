"""Unified entry point dispatcher.

Usage:
- `python main.py` -> starts Microsoft 365 runtime (`main_m365.py`)
- `python main.py cli` -> starts CLI runtime (`main_cli.py`)
"""

import argparse
import runpy


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the desired runtime entrypoint")
    parser.add_argument(
        "mode",
        nargs="?",
        choices=["cli"],
        help="Execution mode. Use 'cli' for local interactive CLI.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    target_module = "main_cli" if args.mode == "cli" else "main_m365"
    runpy.run_module(target_module, run_name="__main__")


if __name__ == "__main__":
    main()
