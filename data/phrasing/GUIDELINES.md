# Phrasing dataset: annotation guidelines

This dataset trains an on-device text classifier that flags Arabic UI text
that reads like a word-for-word (literal) translation from English.

## File format

`phrasing.csv` has three columns:

| Column | Meaning |
|---|---|
| `text` | One Arabic sentence, as it would appear in an app |
| `label` | `literal` or `natural` |
| `note` | Where the example came from: `seed`, `real-app`, `rewritten`, `colleague`… |

Save the file as UTF-8. If a sentence contains a Latin comma `,`, wrap the whole sentence in double quotes.

## Labels

**`literal`**: correct grammar, but a native reader would notice it was translated. Typical signs:

- `قام بـ` + masdar instead of a direct verb (قام بتحديث → حدّث)
- `يتم` / `تم` + masdar for a simple passive (يتم تحميل → جارٍ تحميل)
- `بواسطة` for an agent
- `الخاص بك` instead of a possessive suffix (كلمة المرور الخاصة بك → كلمة مرورك)
- an extra pronoun or copula copied from English (أنت لديك، هو غير متاح)
- `لكي` / `من أجل` where `لـ` is enough
- English idioms carried over (دعنا نبدأ، شكرًا لك على كونك)

**`natural`**: reads as if it was written in Arabic in the first place.

## Rules

1. Judge naturalness only. Do not label a sentence `literal` because of a spelling, glossary or punctuation problem; the app already checks those.
2. Modern Standard Arabic, UI register (buttons, alerts, settings, onboarding).
3. One sentence per row. Keep numbers and placeholders such as `{name}` as they are.
4. When you are unsure, leave the row out rather than guess.
5. Aim for a balance: about as many `literal` rows as `natural` rows.
6. Pairs help: a literal sentence and its natural rewrite teach the model the difference. Single sentences from real apps are just as useful.

## How much data

| Rows | What to expect |
|---|---|
| 50 (seed) | Enough to test the pipeline, not to trust the model |
| 200–300 | First useful model |
| 500+ | Good enough to ship next to the rule-based check |

The 48 `seed` rows were drafted to start the pipeline. Review each one, fix or remove any you disagree with, and change `seed` to `reviewed` once checked.
