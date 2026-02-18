"""
Text Transformation API Routes

Endpoints for transforming text using the local LLM.
Mounted as part of the main FastAPI app in server.py.
"""

import asyncio
import threading

from fastapi import APIRouter, HTTPException

from .server_helpers import (
    TransformDownloadResponse,
    TransformRequest,
    TransformResponse,
    TransformStatusResponse,
)
from .startup import transform_executor
from .transform import TextTransformer, TransformError
from .transform_prompts import AVAILABLE_TRANSFORMATIONS

router = APIRouter()

# Shared text transformer instance (lazy-loads the LLM)
_text_transformer = TextTransformer()


@router.post("/transform", response_model=TransformResponse)
async def transform_text(request: TransformRequest):
    """
    Transform text using the local LLM.

    Accepts text and a transformation type, returns the transformed version.
    Runs in a separate thread pool so it doesn't block transcription.
    """
    loop = asyncio.get_running_loop()

    try:
        transformed = await loop.run_in_executor(
            transform_executor,
            lambda: _text_transformer.transform(
                request.text, request.transformation_type
            ),
        )
    except TransformError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transformation failed: {str(e)}")

    return TransformResponse(
        original_text=request.text,
        transformed_text=transformed,
        transformation_type=request.transformation_type,
        status="success",
    )


@router.get("/transform/status", response_model=TransformStatusResponse)
async def get_transform_status():
    """Get the status of the transformation LLM model."""
    mgr = _text_transformer.model_manager
    return TransformStatusResponse(
        model_loaded=mgr.is_model_loaded,
        model_downloaded=mgr.is_model_downloaded,
        model_downloading=mgr.is_downloading,
        available_types=AVAILABLE_TRANSFORMATIONS,
        download_error=mgr.download_error,
    )


@router.post("/transform/download", response_model=TransformDownloadResponse)
async def download_transform_model():
    """Start downloading the transformation LLM model in the background."""
    mgr = _text_transformer.model_manager

    if mgr.is_downloading:
        return TransformDownloadResponse(status="downloading")
    if mgr.is_model_downloaded:
        return TransformDownloadResponse(status="ready")

    def do_download():
        mgr.download_model()

    thread = threading.Thread(target=do_download, daemon=True)
    thread.start()

    return TransformDownloadResponse(status="downloading")


@router.get("/transform/download_status", response_model=TransformDownloadResponse)
async def get_transform_download_status():
    """Get the download status of the transformation model."""
    mgr = _text_transformer.model_manager

    if mgr.is_downloading:
        return TransformDownloadResponse(status="downloading")
    if mgr.download_error:
        return TransformDownloadResponse(status="error", error=mgr.download_error)
    if mgr.is_model_downloaded:
        return TransformDownloadResponse(status="ready")

    return TransformDownloadResponse(status="not_downloaded")
