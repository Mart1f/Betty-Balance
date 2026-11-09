# BettyBalance

A personal finance app with on-device AI transaction classification, built with Flutter and Supabase.

## Why it exists

It started from a concrete need: having one place to see all my expenses and income without relying on individual bank apps, which are limited, slow, and don't talk to each other. I have accounts at BNP (France), Revolut, and BBVA Colombia, in euros and Colombian pesos, and I wanted to see everything together, categorized and in a way that actually makes sense.

Two technical interests shaped the approach: exploring Flutter as a tool for building apps that run on different devices without rewriting code, and connecting to a real, secure, open-source database that I actually control. A third thread emerged during development: building a local ML classification pipeline that runs entirely on-device using ONNX, trained on real transaction data.

## What it does

**Import bank statements**
Upload your bank statement (CSV for Revolut, PDF for BNP) and the app reads it, extracts every transaction, and saves it. No manual forms, no copying anything by hand.

**AI-powered automatic classification**
Every transaction is classified automatically the moment it's imported. The classification pipeline runs in two stages: a fast keyword layer handles obvious patterns (merchant names, known payees), and a machine learning model — trained on real transactions from this app — handles everything the keyword layer doesn't recognize with confidence.

The ML model is a TF-IDF + Logistic Regression classifier exported to ONNX format. ONNX (Open Neural Network Exchange) is an open standard for packaging trained models so they can run anywhere, on any device, without needing Python or a server. In BettyBalance, the model runs entirely on-device via ONNX Runtime — no API calls, no cloud, no latency.

The model was trained on 1,178 labeled transactions across 13 categories. Cross-validation on that dataset gives **86.8% accuracy (± 5.2%)**, meaning 9 out of 10 transactions are categorized correctly without any user input. The model can be retrained at any time as more transactions accumulate, and the ONNX file is replaced in the app bundle.

**Unified view across all accounts**
A single table with all movements from all banks, with filters by date, category, and bank. The total balance is always visible at the top.

**Monthly summary and charts**
An analytics panel shows month by month how much came in, how much went out, where the money went (category breakdown), and what the savings margin was. It includes month-over-month comparisons to spot trends.

**Multi-currency**
Handles EUR and COP natively, without forced conversions.

## Why Flutter

Flutter lets you build one app that runs on Windows, Android, and iOS without changing the core logic. For a personal project, that means developing comfortably on a PC and using it on a phone or tablet without extra work. It also uses a modern language (Dart) with an active ecosystem and solid documentation.

## Why Supabase

Supabase is an open-source database platform built on PostgreSQL. There are three reasons for choosing it:

1. **Full control over the data** — financial data is private. With Supabase I can self-host if I want, or use their cloud service knowing no third party is monetizing my information.
2. **Security by design** — it has Row Level Security enabled, meaning each user can only see their own data, enforced at the database level. No bug can accidentally expose someone else's records.
3. **Real-time sync** — a change made on Windows shows up on the phone within seconds, with no need to build a custom API.

## Supported banks

| Bank | Format | Status |
|---|---|---|
| Revolut | CSV | ✅ Working (ES/EN) |
| BNP Paribas | PDF | ✅ Working |
| BBVA Colombia | PDF | 🔜 Pending |

## Platforms

| Platform | Status |
|---|---|
| Windows | ✅ |
| Android | ✅ |
| iOS | 🔜 Pending |

## What's next

**Category assignment during import**
Instead of classifying after the fact, being able to review and confirm categories as part of the import flow, before anything is saved.

**Deeper money management**
Richer tools around budgets, spending limits by category, and a clearer picture of financial health over time — not just what happened, but whether it was sustainable.

**Credit cards and debt tracking**
A dedicated module for credit cards and loans: installment breakdown, total debt exposure, payment capacity, statement closing dates, and how different debts interact with each other month to month.

**Accounting calendar**
A view oriented around tax obligations — annual declarations, withholdings, and country-specific deadlines — to make it useful not just for day-to-day tracking but for the bigger financial picture at the end of the year.
