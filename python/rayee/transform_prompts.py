"""
Prompt Templates for Text Transformations

Defines the system/user prompts for each transformation type.
Each prompt instructs the LLM to transform text in a specific way.
"""

from enum import Enum

AVAILABLE_TRANSFORMATIONS = ["grammar", "bullets", "rephrase", "formal", "casual"]


class TransformationType(str, Enum):
    GRAMMAR = "grammar"
    BULLETS = "bullets"
    REPHRASE = "rephrase"
    FORMAL = "formal"
    CASUAL = "casual"


# System prompt shared by all transformations
SYSTEM_PROMPT = (
    "You are a text transformation assistant. "
    "You ONLY output the transformed text, nothing else. "
    "No explanations, no preamble, no quotes around the output."
)

# Per-type user prompt templates. {text} is replaced with the input.
PROMPT_TEMPLATES = {
    TransformationType.GRAMMAR: (
        "Fix the grammar, spelling, and punctuation in the following text. "
        "Keep the original meaning and tone. Do not add or remove content.\n\n"
        "{text}"
    ),
    TransformationType.BULLETS: (
        "Convert the following text into a clean bullet point list. "
        "Each bullet should be concise. Use - for bullets.\n\n"
        "{text}"
    ),
    TransformationType.REPHRASE: (
        "Rephrase the following text to be clearer and more concise. "
        "Keep the same meaning but improve readability.\n\n"
        "{text}"
    ),
    TransformationType.FORMAL: (
        "Rewrite the following text in a formal, professional tone. "
        "Keep the same meaning.\n\n"
        "{text}"
    ),
    TransformationType.CASUAL: (
        "Rewrite the following text in a casual, friendly tone. "
        "Keep the same meaning.\n\n"
        "{text}"
    ),
}


def build_prompt(text: str, transformation_type: str) -> tuple[str, str]:
    """Build the system and user prompts for a transformation.

    Args:
        text: The text to transform.
        transformation_type: One of the AVAILABLE_TRANSFORMATIONS.

    Returns:
        Tuple of (system_prompt, user_prompt).

    Raises:
        ValueError: If transformation_type is invalid.
    """
    try:
        t_type = TransformationType(transformation_type)
    except ValueError:
        raise ValueError(
            f"Unknown transformation type: {transformation_type}. "
            f"Available: {AVAILABLE_TRANSFORMATIONS}"
        )

    user_prompt = PROMPT_TEMPLATES[t_type].format(text=text)
    return SYSTEM_PROMPT, user_prompt
