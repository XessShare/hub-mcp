"""fitnaai CLI entry point."""

import argparse
import sys


def main() -> None:
    """Main CLI entry point for `fitnaai` command."""
    parser = argparse.ArgumentParser(
        prog="fitnaai",
        description="AI-powered fitness and nutrition assistant",
    )
    parser.add_argument("--version", action="version", version="%(prog)s 0.1.0")

    subparsers = parser.add_subparsers(dest="command")

    # fitnaai serve
    serve_parser = subparsers.add_parser("serve", help="Start the API server")
    serve_parser.add_argument("--host", default="0.0.0.0")
    serve_parser.add_argument("--port", type=int, default=8000)

    # fitnaai check
    subparsers.add_parser("check", help="Check system dependencies and connectivity")

    args = parser.parse_args()

    if args.command == "serve":
        from fitnaai.server import run

        run()
    elif args.command == "check":
        _run_checks()
    else:
        parser.print_help()
        sys.exit(1)


def _run_checks() -> None:
    """Verify that external dependencies (Ollama, GPU) are reachable."""
    import httpx

    from fitnaai.config import settings

    print(f"fitnaai system check")
    print(f"  Ollama URL: {settings.ollama_base_url}")

    try:
        resp = httpx.get(f"{settings.ollama_base_url}/api/tags", timeout=5)
        models = resp.json().get("models", [])
        print(f"  Ollama:     OK ({len(models)} models available)")
        for m in models:
            print(f"    - {m['name']}")
    except Exception as e:
        print(f"  Ollama:     FAIL ({e})")


if __name__ == "__main__":
    main()
