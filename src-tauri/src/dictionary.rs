use rusqlite::{Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use unicode_normalization::UnicodeNormalization;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub word: String,
    pub phonetic: String,
    pub translation: String,
    pub definition: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Relation {
    pub lemma: String,
    pub relation: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Card {
    pub original: String,
    pub entry: Entry,
    pub relations: Vec<Relation>,
    pub confirmed: bool,
    pub source: String,
}

pub fn normalize(text: &str) -> String {
    text.nfkc()
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn entry(db: &Connection, key: &str) -> Result<Option<Entry>, String> {
    db.query_row(
        "SELECT word,phonetic,translation,definition FROM entries WHERE key=?",
        [key],
        |row| {
            Ok(Entry {
                word: row.get(0)?,
                phonetic: row.get(1)?,
                translation: row.get(2)?,
                definition: row.get(3)?,
            })
        },
    )
    .optional()
    .map_err(|e| e.to_string())
}

pub fn lookup(db: &Connection, text: &str) -> Result<Option<Card>, String> {
    let key = normalize(text);
    let exact = entry(db, &key)?;
    let mut statement = db
        .prepare("SELECT lemma,relation,pure FROM forms WHERE form=? ORDER BY lemma,relation")
        .map_err(|e| e.to_string())?;
    let rows = statement
        .query_map([&key], |row| {
            Ok((
                Relation {
                    lemma: row.get(0)?,
                    relation: row.get(1)?,
                },
                row.get::<_, bool>(2)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let forms = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    let unique = forms
        .first()
        .filter(|(first, _)| forms.iter().all(|(other, _)| first.lemma == other.lemma));
    let pure = unique.is_some() && forms.iter().all(|(_, pure)| *pure);
    let resolved = if pure || exact.is_none() {
        if let Some((relation, _)) = unique {
            entry(db, &relation.lemma)?.or(exact)
        } else {
            exact
        }
    } else {
        exact
    };
    let confirmed = pure || forms.is_empty();
    Ok(resolved.map(|entry| Card {
        original: text.trim().to_string(),
        entry,
        relations: forms.into_iter().map(|(relation, _)| relation).collect(),
        confirmed,
        source: "ECDICT".into(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn dictionary() -> Connection {
        Connection::open_with_flags(
            concat!(env!("CARGO_MANIFEST_DIR"), "/resources/dictionary.sqlite"),
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )
        .unwrap()
    }
    #[test]
    fn reviewed_plural_resolves_but_keeps_original() {
        let card = lookup(&dictionary(), "quantities").unwrap().unwrap();
        assert_eq!(card.entry.word, "quantity");
        assert_eq!(card.original, "quantities");
        assert!(card.confirmed);
    }
    #[test]
    fn independent_meanings_survive_morphology() {
        for (word, meaning, lemma) in [("goods", "货物", "good"), ("saw", "锯", "see")] {
            let card = lookup(&dictionary(), word).unwrap().unwrap();
            assert_eq!(card.entry.word, word);
            assert!(card.entry.translation.contains(meaning));
            assert!(card.relations.iter().any(|r| r.lemma == lemma));
            assert!(!card.confirmed);
        }
    }
    #[test]
    fn phrases_are_looked_up_whole() {
        let card = lookup(&dictionary(), "  TAKE  OFF ").unwrap().unwrap();
        assert_eq!(card.entry.word, "take off");
        assert!(
            lookup(
                &dictionary(),
                "this is a sentence that is not a dictionary entry"
            )
            .unwrap()
            .is_none()
        );
    }
}
