export interface Card {
  original: string;
  entry: {
    word: string;
    phonetic: string;
    translation: string;
    definition: string;
  };
  relations: { lemma: string; relation: string }[];
  confirmed: boolean;
  source: string;
}
export interface Prepared {
  source: string;
  target: string;
  mode: "dictionary" | "translation";
  card: Card | null;
}
export interface Settings {
  endpoint: string;
  model: string;
  shortcuts: [string, string, string];
}
export interface SavedWord {
  id: string;
  card: Card;
  source_language: string;
  target_language: string;
  contexts: string[];
  saved_at: number;
}
