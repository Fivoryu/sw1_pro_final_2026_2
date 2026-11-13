"""Create listing reviews and review reports (F14.8).

Revision ID: 0034_listing_reviews
Revises: 0033_notifications
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0034_listing_reviews"
down_revision: Union[str, Sequence[str], None] = "0033_notifications"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "listing_review",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("customer_id", sa.String(length=36), nullable=False),
        sa.Column("listing_rating", sa.Integer(), nullable=False),
        sa.Column("agency_rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("agency_reply", sa.Text(), nullable=True),
        sa.Column("agency_reply_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("agency_reply_by", sa.String(length=36), nullable=True),
        sa.Column("hidden_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agency_id"], ["agency.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customer_account.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agency_reply_by"], ["staff_account.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("listing_id", "customer_id", name="uq_listing_review_listing_customer"),
        sa.CheckConstraint("listing_rating BETWEEN 1 AND 5", name="ck_listing_review_listing_rating"),
        sa.CheckConstraint("agency_rating BETWEEN 1 AND 5", name="ck_listing_review_agency_rating"),
    )
    op.create_index("ix_listing_review_agency_id", "listing_review", ["agency_id"])

    op.create_table(
        "review_report",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("review_id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("reporter_id", sa.String(length=36), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_by", sa.String(length=36), nullable=True),
        sa.ForeignKeyConstraint(["review_id"], ["listing_review.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agency_id"], ["agency.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reporter_id"], ["staff_account.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["resolved_by"], ["staff_account.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "status IN ('open', 'upheld', 'dismissed')", name="ck_review_report_status"
        ),
    )
    op.create_index("ix_review_report_review_id", "review_report", ["review_id"])


def downgrade() -> None:
    op.drop_index("ix_review_report_review_id", table_name="review_report")
    op.drop_table("review_report")
    op.drop_index("ix_listing_review_agency_id", table_name="listing_review")
    op.drop_table("listing_review")
