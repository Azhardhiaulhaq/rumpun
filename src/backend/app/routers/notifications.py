"""Register the current signed-in user's FCM device token."""

from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import PushDevice, utcnow
from app.push import token_digest
from app.security import AuthContext, get_auth_context

router = APIRouter(prefix="/notifications", tags=["notifications"])


class DeviceRequest(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: Literal["android", "ios"]


@router.post("/devices", status_code=204)
def register_device(
    payload: DeviceRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> None:
    digest = token_digest(payload.token)
    device = db.scalar(select(PushDevice).where(PushDevice.token_digest == digest))
    if device is None:
        device = PushDevice(token_digest=digest, token=payload.token)
        db.add(device)
    device.user_id = auth.user.id
    device.household_id = auth.household.id
    device.platform = payload.platform
    device.updated_at = utcnow()
    db.commit()


@router.delete("/devices", status_code=204)
def unregister_device(
    payload: DeviceRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> None:
    device = db.scalar(
        select(PushDevice).where(
            PushDevice.token_digest == token_digest(payload.token),
            PushDevice.user_id == auth.user.id,
        )
    )
    if device is not None:
        db.delete(device)
        db.commit()
