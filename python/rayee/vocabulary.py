"""
Vocabulary Management Module

Stores custom words/phrases that you want the AI to recognize better.
These could be names, technical terms, jargon, etc.

The words are saved to a JSON file and passed to Whisper as "hints"
during transcription, which helps it recognize them correctly.
"""

import json
import os
from pathlib import Path
from typing import List, Set


# Where vocabulary is stored - in your home directory so it persists
DEFAULT_VOCAB_PATH = Path.home() / ".rayee" / "vocabulary.json"


class VocabularyManager:
    """
    Manages custom vocabulary words for better transcription accuracy.

    Words you add here are given to the Whisper AI as "hints" which
    helps it recognize uncommon names, technical terms, etc.

    Usage:
        vocab = VocabularyManager()
        vocab.add_word("Rayee")
        vocab.add_word("FastAPI")

        # Get words as a hint for transcription
        prompt = vocab.get_prompt()  # "Rayee, FastAPI"
    """

    def __init__(self, vocab_path: Path = DEFAULT_VOCAB_PATH):
        """
        Initialize the vocabulary manager.

        Args:
            vocab_path: Where to save the vocabulary file (default: ~/.rayee/vocabulary.json)
        """
        self.vocab_path = vocab_path
        self._words: Set[str] = set()
        self._load()

    def _load(self):
        """Load vocabulary from the JSON file."""
        if self.vocab_path.exists():
            try:
                with open(self.vocab_path, 'r') as f:
                    data = json.load(f)
                    self._words = set(data.get("words", []))
            except (json.JSONDecodeError, IOError) as e:
                print(f"Warning: Could not load vocabulary: {e}")
                self._words = set()
        else:
            self._words = set()

    def _save(self):
        """Save vocabulary to the JSON file."""
        # Create the directory if it doesn't exist
        self.vocab_path.parent.mkdir(parents=True, exist_ok=True)

        with open(self.vocab_path, 'w') as f:
            json.dump({"words": sorted(list(self._words))}, f, indent=2)

    def add_word(self, word: str) -> bool:
        """
        Add a word to the vocabulary.

        Args:
            word: The word or phrase to add

        Returns:
            True if the word was added, False if it already existed
        """
        word = word.strip()
        if not word:
            return False

        if word in self._words:
            return False

        self._words.add(word)
        self._save()
        return True

    def remove_word(self, word: str) -> bool:
        """
        Remove a word from the vocabulary.

        Args:
            word: The word to remove

        Returns:
            True if the word was removed, False if it wasn't in the vocabulary
        """
        word = word.strip()
        if word not in self._words:
            return False

        self._words.discard(word)
        self._save()
        return True

    def get_words(self) -> List[str]:
        """Get all vocabulary words as a sorted list."""
        return sorted(list(self._words))

    def get_prompt(self) -> str:
        """
        Get vocabulary as a prompt string for Whisper.

        This format works well as an initial_prompt for Whisper,
        helping it recognize these words during transcription.

        Returns:
            Comma-separated string of words, or empty string if no words
        """
        if not self._words:
            return ""
        return ", ".join(sorted(self._words))

    def clear(self):
        """Remove all words from the vocabulary."""
        self._words.clear()
        self._save()

    def count(self) -> int:
        """Get the number of words in the vocabulary."""
        return len(self._words)
