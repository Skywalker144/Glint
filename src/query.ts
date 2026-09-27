export type Mode = "dictionary" | "translation";

export class QueryState {
  input = "";
  output = "";
  source = "auto";
  target = "auto";
  resolvedSource = "";
  resolvedTarget = "";
  mode: Mode = "dictionary";
  stale = false;
  complete = false;
  request = 0;

  open(text: string) {
    this.edit(text);
    this.source = this.target = "auto";
    this.resolvedSource = this.resolvedTarget = "";
    this.output = "";
    this.stale = false;
  }

  edit(text: string) {
    this.input = text;
    this.stale = true;
    this.complete = false;
    this.request++;
  }

  begin() {
    this.stale = true;
    this.complete = false;
    return ++this.request;
  }

  accept(id: number, text: string) {
    if (id !== this.request) return false;
    this.output = text;
    this.stale = false;
    return true;
  }

  swap() {
    if (!this.resolvedSource || !this.resolvedTarget) return false;
    const translate =
      this.mode === "translation" &&
      this.complete &&
      !this.stale &&
      !!this.output;
    this.source = this.resolvedTarget;
    this.target = this.resolvedSource;
    this.edit(translate ? this.output : this.input);
    return translate;
  }
}
