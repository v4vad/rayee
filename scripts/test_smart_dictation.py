#!/usr/bin/env python3
"""
Test Smart Dictation prompt against Ollama models.
Uses the exact prompt from docs/plans/2026-05-14-001-feat-smart-dictation-auto-transform-plan.md
"""

import json
import urllib.request
import sys

OLLAMA_URL = "http://localhost:11434/api/generate"

SYSTEM_PROMPT = "You are a voice dictation processor. Receive raw speech and output only the final clean text. No explanations."

USER_TEMPLATE = """Clean up this dictated speech:
- Fix grammar, punctuation, and sentence structure
- Remove filler words (uh, um, like, you know)
- Convert spoken punctuation to symbols ("comma" → ,  "period" → .  "new paragraph" → paragraph break)
- Preserve the speaker's words and meaning exactly — do not rephrase, summarize, or add content
Output only the cleaned text, nothing else.

Text: {text}"""

PHRASES = [
    # Category 1 — Structure commands
    {
        "num": 1,
        "category": "Structure",
        "input": "Call Sarah tomorrow next point buy milk next point check emails",
        "expected": "3-bullet list",
        "critical": False,
    },
    {
        "num": 2,
        "category": "Structure",
        "input": "Intro paragraph new paragraph main body new paragraph conclusion",
        "expected": "3 separate paragraphs",
        "critical": False,
    },
    {
        "num": 3,
        "category": "Structure",
        "input": "Budget summary make that a heading total expenses are five hundred dollars",
        "expected": "# Budget Summary then the sentence",
        "critical": False,
    },
    {
        "num": 4,
        "category": "Structure",
        "input": "The key insight bold that is that speed matters",
        "expected": 'The key insight **is that speed matters**',
        "critical": False,
    },
    # Category 2 — Remove/replace commands
    {
        "num": 5,
        "category": "Remove/Replace",
        "input": "Meeting at 3pm scratch that meeting at 4pm",
        "expected": "Meeting at 4pm.",
        "critical": False,
    },
    {
        "num": 6,
        "category": "Remove/Replace",
        "input": "I need to finish the report by Friday actually make it next Monday",
        "expected": "I need to finish the report by next Monday.",
        "critical": False,
    },
    {
        "num": 7,
        "category": "Remove/Replace",
        "input": "Email the client delete that call the client",
        "expected": "Call the client.",
        "critical": False,
    },
    {
        "num": 8,
        "category": "Remove/Replace",
        "input": "The deadline is Thursday actually the deadline is Friday",
        "expected": "The deadline is Friday.",
        "critical": False,
    },
    # Category 3 — Command-like content (CRITICAL — must NOT be edited)
    {
        "num": 9,
        "category": "CRITICAL: Content not command",
        "input": "Write a note about how to remove paint from a wall",
        "expected": "verbatim (no editing of content)",
        "critical": True,
    },
    {
        "num": 10,
        "category": "CRITICAL: Content not command",
        "input": "The next point of contact is Bob in accounting",
        "expected": "verbatim (no bullet created)",
        "critical": True,
    },
    {
        "num": 11,
        "category": "CRITICAL: Content not command",
        "input": "Can you scratch that old invoice and send a new one",
        "expected": 'verbatim ("scratch that" is content)',
        "critical": True,
    },
    {
        "num": 12,
        "category": "CRITICAL: Content not command",
        "input": "My doctor said to actually start taking the medication now",
        "expected": 'verbatim ("actually" is not replace command)',
        "critical": True,
    },
    {
        "num": 13,
        "category": "CRITICAL: Content not command",
        "input": "Delete all the old files from the backup folder",
        "expected": "verbatim (delete is content not self-referential)",
        "critical": True,
    },
    {
        "num": 14,
        "category": "Ambiguous",
        "input": "She said make that formal for the board presentation",
        "expected": "AMBIGUOUS — record behavior",
        "critical": False,
    },
    # Category 4 — Mixed real dictation
    {
        "num": 15,
        "category": "Mixed",
        "input": "uh the meeting went well comma we discussed the budget next point action item one is to send the report",
        "expected": "clean prose + bullet point",
        "critical": False,
    },
    {
        "num": 16,
        "category": "Mixed",
        "input": "i need to buy groceries scratch that I already went shopping",
        "expected": "I already went shopping.",
        "critical": False,
    },
    {
        "num": 17,
        "category": "Mixed",
        "input": "remind me to call mom tomorrow make that formal",
        "expected": "formal rewrite",
        "critical": False,
    },
    {
        "num": 18,
        "category": "Mixed",
        "input": "the project deadline is next week actually remove that we don't have a deadline yet",
        "expected": "We don't have a deadline yet.",
        "critical": False,
    },
    # Category 5 — Edge cases
    {
        "num": 19,
        "category": "Edge",
        "input": "delete that",
        "expected": "empty or near-empty",
        "critical": False,
    },
    {
        "num": 20,
        "category": "Edge",
        "input": "I had a great meeting with the team and we aligned on the roadmap",
        "expected": "grammar-fixed, nothing removed or changed",
        "critical": False,
    },
]


def query_model(model: str, text: str) -> str:
    prompt = USER_TEMPLATE.format(text=text)
    payload = {
        "model": model,
        "system": SYSTEM_PROMPT,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.0},
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result.get("response", "").strip()


def run_tests(model: str):
    print(f"\n{'='*80}")
    print(f"MODEL: {model}")
    print(f"{'='*80}\n")

    results = []
    for phrase in PHRASES:
        num = phrase["num"]
        category = phrase["category"]
        inp = phrase["input"]
        expected = phrase["expected"]
        critical = phrase["critical"]

        print(f"  [{num:02d}] Testing: {inp[:60]}...")
        sys.stdout.flush()

        try:
            output = query_model(model, inp)
        except Exception as e:
            output = f"ERROR: {e}"

        results.append(
            {
                "num": num,
                "category": category,
                "input": inp,
                "expected": expected,
                "output": output,
                "critical": critical,
            }
        )
        print(f"       → {output[:120]}")
        sys.stdout.flush()

    return results


def print_table(model: str, results: list):
    print(f"\n\n{'='*80}")
    print(f"RESULTS TABLE — {model}")
    print(f"{'='*80}")
    print(f"{'#':<3} {'Cat':<28} {'Input (truncated)':<40} {'Output (truncated)':<50} {'Pass/Fail'}")
    print("-" * 130)
    for r in results:
        num = r["num"]
        cat = r["category"][:27]
        inp = r["input"][:38]
        out = r["output"][:48]
        # Pass/fail logic
        if r["category"].startswith("CRITICAL"):
            # Check if content was preserved verbatim or near-verbatim
            # Fail if output is empty or clearly different sentence structure
            inp_words = set(r["input"].lower().split())
            out_words = set(r["output"].lower().split())
            overlap = len(inp_words & out_words) / max(len(inp_words), 1)
            pf = "PASS" if overlap >= 0.7 else "FAIL *CRITICAL*"
        elif num == 14:
            pf = "AMBIGUOUS"
        elif num == 19:
            pf = "PASS" if len(r["output"].strip()) <= 20 else "NOTE: not empty"
        elif num in (1, 2, 15):
            # Expect bullet(s) or paragraph breaks
            pf = "PASS" if "-" in r["output"] or "\n\n" in r["output"] else "FAIL"
        elif num == 3:
            pf = "PASS" if "#" in r["output"] else "FAIL"
        elif num == 4:
            pf = "PASS" if "**" in r["output"] else "FAIL"
        elif num in (5, 6, 7, 8, 16, 18):
            pf = "CHECK"  # Needs manual verification
        elif num == 17:
            pf = "CHECK"
        elif num == 20:
            # Should be close to verbatim
            inp_words = set(r["input"].lower().split())
            out_words = set(r["output"].lower().split())
            overlap = len(inp_words & out_words) / max(len(inp_words), 1)
            pf = "PASS" if overlap >= 0.6 else "FAIL"
        else:
            pf = "CHECK"

        print(f"{num:<3} {cat:<28} {inp:<40} {out:<50} {pf}")

    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_smart_dictation.py <model_name>")
        print("Example: python test_smart_dictation.py llama3.2:1b")
        sys.exit(1)

    model = sys.argv[1]
    results = run_tests(model)
    print_table(model, results)

    # Also dump full outputs for manual review
    print(f"\n{'='*80}")
    print("FULL OUTPUTS (for manual review)")
    print(f"{'='*80}")
    for r in results:
        print(f"\n[{r['num']:02d}] {r['category']}")
        print(f"  INPUT:    {r['input']}")
        print(f"  EXPECTED: {r['expected']}")
        print(f"  OUTPUT:   {r['output']}")
        if r["critical"]:
            print("  *** CRITICAL TEST ***")
