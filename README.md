# Booksmith

A flexible book publishing CLI tool that converts Markdown chapters into professionally styled PDF and EPUB books using Prawn, GEPUB, and Kramdown.

## Features

- **Multi-format output**: Compile to PDF, EPUB, or both simultaneously.
- **Custom typography & layouts**: Full control over font sizes, line heights, margins, and page breaks via `config/book.yml`.
- **Bundled Noto fonts**: Comes bundled with Noto Sans and Noto Sans Mono so your publications render cleanly without external font dependencies.
- **Rich Markdown callouts**:
  - Auto-detected bold header callout boxes
  - Alternate shaded callout boxes (`{: .alt_blockquote}`)
  - Exercise callout boxes (`{: .exercise_blockquote}`) with customizable icon support
- **Subtitles & Print-ready Page Breaks**: Invisible HTML comment syntax for metadata and layout control.
- **Image handling**: Markdown title attributes for sizing (`width=350 top=10 bottom=10`), horizontal centering, and automatic checkerboard background flattening via ImageMagick.

---

## Installation

Install via RubyGems:

```sh
gem install booksmith
```

Or add to your project's `Gemfile`:

```ruby
gem 'booksmith'
```

---

## Usage

### 1. Initialize a new book project

```sh
mkdir my-book
cd my-book
booksmith init
```

This creates the standard project directory structure and copies default configuration and starter files:
- `assets/`: Image assets and icon files (includes default `clock.png`)
- `chapters/`: Markdown chapters (includes sample `01_introduction.md`)
- `config/`: Configuration files (includes sample `book.yml`)

### 2. Build your book

```sh
# Generate book.pdf (default)
booksmith build

# Generate book.epub
booksmith build --epub

# Generate both PDF and EPUB
booksmith build --format all

# Skip the cover page
booksmith build --no-cover
```

### 3. Check registered fonts

```sh
booksmith fonts
```

---

## Configuration

All book metadata, typography, and styling settings live in `config/book.yml`.

Example snippet:

```yaml
---
:title: "My Book"
:author: Authored by Author Name

# Fonts
:title_font: "Noto Sans Mono"
:author_font: "Noto Sans Mono"
:header_font: "Noto Sans"
:subtitle_font: "Noto Sans Mono"
:body_font: "Noto Sans"

# Layout
:blank_page_after_cover: true
:table_of_contents: true
:font_size: 10.0
:line_height: 1.5

# Header sizes
:title_font_size: 24
:author_font_size: 18
:h1_font_size: 20
:h2_font_size: 18
:h3_font_size: 14
:h4_font_size: 12
```

---

## Markdown Conventions

- **Numbered chapter files**: Place `.md` files in `chapters/` (sorted alphabetically, e.g. `01_intro.md`, `02_chapter.md`).
- **Chapter title**: Each chapter must start with `# Title`.
- **Subtitle**: Add directly under the `#` title using an HTML comment:
  ```markdown
  # Chapter 1
  <!-- subtitle: GETTING STARTED -->
  ```
- **Page break**: Force a new page at any point:
  ```markdown
  <!-- PAGE_BREAK -->
  ```
- **Callout boxes**:
  ```markdown
  > **Note Title**
  >
  > Standard callout content.

  > **Sidebar**
  >
  > Alternate callout content.
  {: .alt_blockquote}

  > Exercise Name
  >
  > Hands-on exercise prompt.
  {: .exercise_blockquote}
  ```
- **Images**:
  ```markdown
  ![Diagram](assets/diagram.png "width=350 top=10 bottom=10")
  ```

---

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.
