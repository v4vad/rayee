"""
Text Transformation API Routes

Endpoints for transforming text using the local LLM.
Mounted as part of the main FastAPI app in server.py.
"""

import asyncio
import queue
import threading

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

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


@router.post("/transform/warmup")
async def warmup_transform_model():
    """Preload the transform model so the next transform request is instant."""
    mgr = _text_transformer.model_manager

    if mgr.is_model_loaded:
        return {"status": "already_loaded"}
    if not mgr.is_model_downloaded:
        return {"status": "not_downloaded"}
    if mgr.is_downloading:
        return {"status": "downloading"}

    loop = asyncio.get_running_loop()
    loop.run_in_executor(transform_executor, mgr.load_model)

    return {"status": "warming_up"}


@router.post("/transform_stream")
async def transform_text_stream(request: TransformRequest):
    """Transform text and stream tokens as they're generated."""
    # Validate synchronously first
    try:
        _text_transformer._validate_input(request.text, request.transformation_type)
    except (TransformError, ValueError) as e:
        raise HTTPException(status_code=400, detail=str(e))

    async def generate():
        loop = asyncio.get_running_loop()
        token_queue = queue.Queue()

        def producer():
            try:
                for token in _text_transformer.transform_stream(
                    request.text, request.transformation_type
                ):
                    token_queue.put(token)
            except Exception as e:
                token_queue.put(e)
            finally:
                token_queue.put(None)  # Sentinel

        loop.run_in_executor(transform_executor, producer)

        while True:
            try:
                item = await loop.run_in_executor(
                    None, lambda: token_queue.get(timeout=0.1)
                )
                if item is None:
                    break
                if isinstance(item, Exception):
                    break
                yield item
            except queue.Empty:
                continue

    return StreamingResponse(generate(), media_type="text/plain")


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
