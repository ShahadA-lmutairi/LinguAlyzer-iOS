# How the checks work

All logic lives in the `Analyzer` enum. It takes the source text, the Arabic target, and the glossary, and returns a `Review` with findings and suggestions.

## Score

`score = 100 - penalties`, never below 0.

| Severity | Penalty |
|---|---|
| Critical | 20 |
| Warning | 8 |
| Note | 3 |

The score is a screening indicator only. A clean score does not mean a good translation.

## Checks

1. **Glossary.** For each term, the English word is matched in the source with word boundaries (case-insensitive). If it is found and the Arabic term is not in the target, a warning is added.
2. **Numbers.** Arabic-Indic digits (٠-٩) are converted to 0-9, then numbers are extracted from both texts and compared. A difference is critical.
3. **Placeholders.** Tokens like `{name}`, `%s`, `%1$@`, and `<b>` are extracted from both texts and compared. A difference is critical.
4. **Arabic share.** The share of Arabic letters among all letters in the target. Below 85% adds a note, since names and brands can be intentionally Latin.
5. **Length ratio.** Target length divided by source length. Below 0.4 or above 2.2 adds a flag.
6. **Phrasing.** A small list of literal-translation patterns, each with a reason and, when possible, a replacement.
7. **Punctuation.** `?`, `;`, and `,` in the target, with the Arabic marks `؟ ؛ ،` as replacements. A comma between digits is ignored.
8. **Spacing.** Double spaces.

## Limits

- It does not understand meaning, tone, or dialect.
- The phrasing list is short and should be built with Arabic reviewers.
- Rules are tuned for Modern Standard Arabic.
