#!/usr/bin/env python3
"""
Fetch all transactions categorized as 'Others', run them through the
trained ONNX model, and update Supabase with the new categories.

Usage:
    python reclassify_others.py           # dry run — shows what would change
    python reclassify_others.py --apply   # actually updates Supabase
"""

import os
import sys
import json
import argparse
import numpy as np
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client
import onnxruntime as ort

load_dotenv(Path(__file__).parent.parent / '.env')

SUPABASE_URL      = os.environ.get('SUPABASE_URL')
SUPABASE_KEY      = os.environ.get('SUPABASE_ANON_KEY')
SUPABASE_EMAIL    = os.environ.get('SUPABASE_EMAIL')
SUPABASE_PASSWORD = os.environ.get('SUPABASE_PASSWORD')
MODEL_PATH        = Path(__file__).parent / 'output' / 'classifier.onnx'
LABELS_PATH       = Path(__file__).parent / 'output' / 'labels.json'


def predict_batch(session, labels, descriptions):
    inputs = np.array([[d.lower()] for d in descriptions], dtype=object)
    result = session.run(None, {'input': inputs})
    raw = result[0]
    # result[0] may be shape [N] or [N, 1] depending on skl2onnx version
    if raw.ndim == 2:
        return [row[0] for row in raw]
    return list(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true',
                        help='Write changes to Supabase (default: dry run)')
    args = parser.parse_args()

    if not MODEL_PATH.exists():
        print("Model not found. Run train.py first.")
        sys.exit(1)

    print("Loading model...")
    session = ort.InferenceSession(str(MODEL_PATH))
    with open(LABELS_PATH, encoding='utf-8') as f:
        labels = json.load(f)
    print(f"  Categories: {labels}")

    print("\nConnecting to Supabase...")
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    client.auth.sign_in_with_password({'email': SUPABASE_EMAIL, 'password': SUPABASE_PASSWORD})

    # Fetch all Others
    all_rows = []
    page_size = 1000
    offset = 0
    while True:
        result = (
            client.table('transactions')
            .select('id,description,category')
            .eq('category', 'Others')
            .range(offset, offset + page_size - 1)
            .execute()
        )
        rows = result.data
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        offset += page_size

    if not all_rows:
        print("No 'Others' transactions found.")
        client.auth.sign_out()
        return

    print(f"  {len(all_rows)} transactions with category 'Others'")

    # Predict
    descriptions = [r['description'] for r in all_rows]
    predictions  = predict_batch(session, labels, descriptions)

    # Group by new category for summary
    changes = [(r['id'], r['description'], pred)
               for r, pred in zip(all_rows, predictions)]

    by_category = {}
    for _, desc, cat in changes:
        by_category.setdefault(cat, []).append(desc)

    print("\nPredicted reclassification:")
    for cat, descs in sorted(by_category.items()):
        print(f"  {cat} ({len(descs)})")
        for d in descs[:3]:
            print(f"    · {d}")
        if len(descs) > 3:
            print(f"    · ... and {len(descs) - 3} more")

    if not args.apply:
        print("\nDry run — nothing was changed.")
        print("Run with --apply to update Supabase.")
        client.auth.sign_out()
        return

    # Apply updates in batches
    print("\nUpdating Supabase...")
    batch_size = 100
    updated = 0
    for i in range(0, len(changes), batch_size):
        batch = changes[i:i + batch_size]
        for row_id, _, new_cat in batch:
            client.table('transactions') \
                .update({'category': new_cat}) \
                .eq('id', row_id) \
                .execute()
        updated += len(batch)
        print(f"  {updated}/{len(changes)} updated...")

    client.auth.sign_out()
    print(f"\nDone. {len(changes)} transactions reclassified.")


if __name__ == '__main__':
    main()
