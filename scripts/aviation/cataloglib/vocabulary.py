"""Project-authored classification vocabulary.

These terms are not inferred onto aircraft models. A civil airframe can
fly cargo, and a type code does not identify the operation.
"""

from __future__ import annotations

VOCABULARY = {
    "schemaVersion": 1,
    "dataset": "classifications",
    "sourceId": "tailtag-vocabulary",
    "dimensions": [
        {
            "id": "aircraft-role",
            "label": "Aircraft role",
            "values": [
                {"id": "civil", "label": "Civil"},
                {"id": "military", "label": "Military"},
                {"id": "unknown", "label": "Unknown"},
                {"id": "other", "label": "Other"},
            ],
        },
        {
            "id": "operation-type",
            "label": "Operation type",
            "values": [
                {"id": "passenger", "label": "Passenger"},
                {"id": "cargo", "label": "Cargo"},
                {"id": "private", "label": "Private"},
                {"id": "general-aviation", "label": "General aviation"},
                {"id": "government", "label": "Government"},
                {"id": "training", "label": "Training"},
                {"id": "emergency-services", "label": "Emergency services"},
                {"id": "mixed", "label": "Mixed"},
                {"id": "unknown", "label": "Unknown"},
                {"id": "other", "label": "Other"},
            ],
        },
        {
            "id": "operator-tag",
            "label": "Operator tag",
            "values": [
                {"id": "commercial-airline", "label": "Commercial airline"},
                {"id": "cargo-operator", "label": "Cargo operator"},
                {"id": "military-operator", "label": "Military operator"},
                {"id": "government-operator", "label": "Government operator"},
                {"id": "private-operator", "label": "Private operator"},
                {"id": "other", "label": "Other"},
            ],
        },
    ],
}

OPERATOR_TAGS = {value["id"] for dimension in VOCABULARY["dimensions"] if dimension["id"] == "operator-tag" for value in dimension["values"]}

AIRPORT_TYPES = frozenset(
    {
        "balloonport",
        "closed",
        "heliport",
        "large_airport",
        "medium_airport",
        "seaplane_base",
        "small_airport",
    }
)
