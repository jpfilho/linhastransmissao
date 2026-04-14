"""
Pydantic models for AI analysis API requests and responses.
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict
from datetime import datetime


class AnalyzeImageRequest(BaseModel):
    image_url: str = Field(..., description="Full URL to image in Supabase Storage")
    photo_id: str = Field(..., description="Photo ID in the database")


class BoundingBox(BaseModel):
    x: float
    y: float
    width: float
    height: float
    label: str
    confidence: float


class QualityMetrics(BaseModel):
    blur_score: float = Field(0, ge=0, le=100, description="0=very blurry, 100=sharp")
    exposure_score: float = Field(0, ge=0, le=100, description="0=under/overexposed, 100=perfect")
    overall: float = Field(0, ge=0, le=100)


class AnalyzeImageResponse(BaseModel):
    photo_id: str
    vegetation_detected: bool = False
    vegetation_score: float = Field(0, ge=0, le=100)
    fire_signs: bool = False
    fire_score: float = Field(0, ge=0, le=100)
    structural_issue: bool = False
    anomaly_type: Optional[str] = None
    severity_score: float = Field(0, ge=0, le=100)
    confidence: float = Field(0, ge=0, le=1)
    quality: QualityMetrics = QualityMetrics()
    bounding_boxes: List[BoundingBox] = []
    summary: Optional[str] = None
    model_version: str = "v1.0"
    processed_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())


class CompareImagesRequest(BaseModel):
    current_image_url: str
    previous_image_url: str
    photo_atual_id: str
    photo_anterior_id: str
    torre_id: Optional[str] = None


class CompareImagesResponse(BaseModel):
    change_detected: bool = False
    vegetation_growth_level: float = Field(0, ge=0, le=100)
    degradation_level: float = Field(0, ge=0, le=100)
    new_anomaly_detected: bool = False
    comparison_details: Dict = {}


class GenerateSummaryRequest(BaseModel):
    photo_id: str
    image_url: Optional[str] = None
    analysis_data: Optional[Dict] = None


class GenerateSummaryResponse(BaseModel):
    photo_id: str
    content: str
    suggested_action: Optional[str] = None
    risk_interpretation: Optional[str] = None
    model_used: str = "gpt-4o-mini"


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "1.0.0"
    services: Dict = {}

class ParseRocoRequest(BaseModel):
    texto: str
    vao_m: int

class RocoSegmentModel(BaseModel):
    inicio: int
    fim: int
    tipo: str
    status: str = "nao_iniciado"

class ParseRocoResponse(BaseModel):
    segmentos: List[RocoSegmentModel]


class MoondreamAnnotateRequest(BaseModel):
    image_url: str
    photo_id: str
    segmentos_texto: str
