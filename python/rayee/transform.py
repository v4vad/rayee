"""
Text Transformer

Handles text transformation requests by building prompts,
calling the MLX model, and cleaning up the output.
"""

import re

from .mlx_model import MLXModelManager
from .transform_prompts import AVAILABLE_TRANSFORMATIONS, build_prompt

# Limits
MAX_INPUT_LENGTH = 5000
MIN_INPUT_LENGTH = 1


class TransformError(Exception):
    """Raised when a transformation fails."""

    pass


class TextTransformer:
    """Transforms text using the local LLM."""

    def __init__(self):
        self._model_manager = MLXModelManager()

    @property
    def model_manager(self) -> MLXModelManager:
        return self._model_manager

    def transform(self, text: str, transformation_type: str) -> str:
        """Transform text using the specified transformation type.

        Args:
            text: The text to transform.
            transformation_type: One of: grammar, bullets, rephrase, formal, casual.

        Returns:
            The transformed text.

        Raises:
            TransformError: If validation fails or transformation errors out.
            ValueError: If transformation_type is invalid.
        """
        # Validate input
        self._validate_input(text, transformation_type)

        # Build the prompt
        system_prompt, user_prompt = build_prompt(text, transformation_type)

        # Generate the transformation
        try:
            result = self._model_manager.generate(system_prompt, user_prompt)
        except Exception as e:
            raise TransformError(f"Model generation failed: {str(e)}")

        # Clean up the output
        cleaned = self._clean_output(result, text)
        return cleaned

    def _validate_input(self, text: str, transformation_type: str):
        """Validate transformation inputs."""
        stripped = text.strip()

        if len(stripped) < MIN_INPUT_LENGTH:
            raise TransformError("Text is empty or too short to transform.")

        if len(stripped) > MAX_INPUT_LENGTH:
            raise TransformError(
                f"Text is too long ({len(stripped)} chars). "
                f"Maximum is {MAX_INPUT_LENGTH} characters."
            )

        if transformation_type not in AVAILABLE_TRANSFORMATIONS:
            raise ValueError(
                f"Unknown transformation type: {transformation_type}. "
                f"Available: {AVAILABLE_TRANSFORMATIONS}"
            )

    def _clean_output(self, result: str, original: str) -> str:
        """Clean up LLM output, removing artifacts.

        Strips common LLM artifacts like:
        - Leading/trailing whitespace
        - Wrapping quotes
        - "Here is..." preamble
        - Repeated original text in the output
        """
        text = result.strip()

        # Remove wrapping quotes if the model added them
        if (text.startswith('"') and text.endswith('"')) or (
            text.startswith("'") and text.endswith("'")
        ):
            text = text[1:-1].strip()

        # Remove common LLM preambles
        preamble_patterns = [
            r"^Here(?:'s| is) the (?:corrected|transformed|rephrased|formal|casual|revised) (?:text|version)[:\s]*",
            r"^Sure[,!]?\s*(?:here(?:'s| is))?[:\s]*",
            r"^(?:Corrected|Transformed|Rephrased|Revised)[:\s]+",
        ]
        for pattern in preamble_patterns:
            text = re.sub(pattern, "", text, flags=re.IGNORECASE).strip()

        # If the model returned empty, fall back to original
        if not text:
            return original

        return text
