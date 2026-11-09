#!/usr/bin/env python3
"""
Train a transaction classifier on Supabase data and export to ONNX.

Usage:
    pip install -r requirements.txt
    python train.py

Output:
    output/classifier.onnx   — the model (copy to assets/model/)
    output/labels.json       — category names in order (copy to assets/model/)
"""

import os
import json
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import StringTensorType

# Load credentials from project root .env
load_dotenv(Path(__file__).parent.parent / '.env')

SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_KEY = os.environ.get('SUPABASE_ANON_KEY')
SUPABASE_EMAIL = os.environ.get('SUPABASE_EMAIL')
SUPABASE_PASSWORD = os.environ.get('SUPABASE_PASSWORD')

if not SUPABASE_URL or not SUPABASE_KEY:
    print("Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env")
    sys.exit(1)

if not SUPABASE_EMAIL or not SUPABASE_PASSWORD:
    print("Error: SUPABASE_EMAIL and SUPABASE_PASSWORD must be set in .env")
    sys.exit(1)


def fetch_transactions():
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    client.auth.sign_in_with_password({'email': SUPABASE_EMAIL, 'password': SUPABASE_PASSWORD})

    all_rows = []
    page_size = 1000
    offset = 0
    while True:
        result = (
            client.table('transactions')
            .select('description,category')
            .range(offset, offset + page_size - 1)
            .execute()
        )
        rows = result.data
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        offset += page_size

    client.auth.sign_out()
    return all_rows


def main():
    print("Fetching transactions from Supabase...")
    rows = fetch_transactions()
    print(f"  {len(rows)} transactions downloaded")

    # Exclude 'Others' — too noisy, model learns nothing useful from it
    data = [
        (r['description'], r['category'])
        for r in rows
        if r.get('description') and r.get('category') and r['category'] != 'Others'
    ]

    if len(data) < 50:
        print(f"Not enough labeled data: {len(data)} rows (need at least 50, excluding Others).")
        sys.exit(1)

    X = [d[0].lower() for d in data]
    y = [d[1] for d in data]

    categories = sorted(set(y))
    print(f"  {len(X)} usable transactions across {len(categories)} categories:")
    for cat in categories:
        print(f"    {cat}: {y.count(cat)}")

    # char_wb ngrams: works well for merchant names in any language,
    # handles abbreviations and partial matches robustly
    pipeline = Pipeline([
        ('tfidf', TfidfVectorizer(
            analyzer='word',
            ngram_range=(1, 2),
            max_features=5000,
            min_df=1,
            sublinear_tf=True,
        )),
        ('clf', LogisticRegression(
            max_iter=1000,
            C=1.0,
            class_weight='balanced',
            solver='lbfgs',
        )),
    ])

    print("\nRunning cross-validation...")
    n_splits = min(5, min(y.count(c) for c in categories))
    if n_splits >= 2:
        scores = cross_val_score(pipeline, X, y, cv=n_splits, scoring='accuracy')
        print(f"  Accuracy: {scores.mean():.1%} ± {scores.std():.1%}")
    else:
        print("  Skipping CV (some categories have too few samples)")

    print("\nTraining final model...")
    pipeline.fit(X, y)

    print("Exporting to ONNX...")
    initial_type = [('input', StringTensorType([None, 1]))]
    onnx_model = convert_sklearn(pipeline, initial_types=initial_type, target_opset=17)

    out_dir = Path(__file__).parent / 'output'
    out_dir.mkdir(exist_ok=True)

    onnx_path = out_dir / 'classifier.onnx'
    labels_path = out_dir / 'labels.json'

    with open(onnx_path, 'wb') as f:
        f.write(onnx_model.SerializeToString())

    with open(labels_path, 'w', encoding='utf-8') as f:
        json.dump(pipeline.classes_.tolist(), f, ensure_ascii=False, indent=2)

    print(f"\nDone.")
    print(f"  {onnx_path}")
    print(f"  {labels_path}")
    print(f"\nCopy both files to: assets/model/")


if __name__ == '__main__':
    main()
