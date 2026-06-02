// =============================================================
// Civilytics — Typst template for Quarto PDF
// Usage in YAML:
//   format:
//     typst:
//       template: quarto/typst/civilytics-typst.typ
// =============================================================

#let paper-bg   = rgb("#FAF7F2")
#let ink        = rgb("#0E1A2B")
#let ink-2      = rgb("#2B3A52")
#let ink-3      = rgb("#5A6A82")
#let rule       = rgb("#D6CEBD")
#let rule-strong = rgb("#B8AE97")
#let navy       = rgb("#22406A")
#let ember      = rgb("#C25311")
#let ember-dark = rgb("#923D00")
#let plum       = rgb("#6B3A5E")
#let teal       = rgb("#1F6F70")

#let serif-stack = ("Source Serif 4", "Source Serif Pro", "Georgia", "Times New Roman")
#let sans-stack  = ("Inter", "Helvetica Neue", "Arial")
#let display-stack = ("Libre Franklin", "Inter", "Helvetica Neue")
#let mono-stack  = ("JetBrains Mono", "Menlo", "Consolas")

#let civilytics(
  title: none,
  subtitle: none,
  authors: (),
  date: none,
  abstract: none,
  toc: true,
  doc,
) = {
  // Page setup
  set page(
    paper: "us-letter",
    margin: (top: 1in, bottom: 1in, left: 1.1in, right: 1.1in),
    fill: paper-bg,
    header: context {
      if counter(page).get().first() > 1 {
        set text(font: sans-stack, size: 8pt, fill: ink-3, tracking: 0.06em)
        upper[Civilytics Consulting]
        h(1fr)
        upper(if title != none { title } else { "" })
        v(2pt)
        line(length: 100%, stroke: 0.4pt + rule)
      }
    },
    footer: context {
      set text(font: sans-stack, size: 8pt, fill: ink-3)
      line(length: 100%, stroke: 0.4pt + rule)
      v(4pt)
      grid(
        columns: (1fr, auto, 1fr),
        align: (left, center, right),
        [civilytics.consulting],
        counter(page).display("1 / 1", both: true),
        [© 2026]
      )
    },
  )

  // Body text
  set text(font: serif-stack, size: 10.5pt, fill: ink, lang: "en")
  set par(justify: false, leading: 0.6em, first-line-indent: 0pt)

  // Headings
  show heading.where(level: 1): it => {
    v(1.4em)
    block[
      #set text(font: display-stack, weight: 900, size: 22pt, fill: ink, tracking: -0.025em)
      #it.body
    ]
    v(0.2em)
    line(length: 60pt, stroke: 3pt + ember)
    v(0.6em)
  }
  show heading.where(level: 2): it => {
    v(1.1em)
    line(length: 100%, stroke: 0.5pt + rule)
    v(0.5em)
    block[
      #set text(font: display-stack, weight: 800, size: 16pt, fill: ink, tracking: -0.02em)
      #it.body
    ]
    v(0.3em)
  }
  show heading.where(level: 3): it => {
    v(0.8em)
    block[
      #set text(font: display-stack, weight: 700, size: 13pt, fill: ink, tracking: -0.015em)
      #it.body
    ]
    v(0.2em)
  }
  show heading.where(level: 4): it => block[
    #set text(font: sans-stack, weight: 600, size: 11pt, fill: ink-2)
    #it.body
  ]

  // Links
  show link: it => text(fill: navy, underline(it))

  // Inline code
  show raw.where(block: false): it => box(
    fill: rgb("#F2EDE4"),
    inset: (x: 3pt, y: 1pt),
    outset: (y: 2pt),
    radius: 1pt,
    text(font: mono-stack, size: 0.92em, fill: ember-dark)[#it]
  )

  // Code blocks
  show raw.where(block: true): it => block(
    fill: ink,
    width: 100%,
    inset: 12pt,
    radius: 4pt,
  )[
    #set text(font: mono-stack, size: 8.5pt, fill: paper-bg)
    #it
  ]

  // Block quote
  show quote.where(block: true): it => block(
    stroke: (left: 2pt + ember),
    inset: (left: 14pt, top: 4pt, bottom: 4pt),
    spacing: 1.2em,
  )[
    #set text(font: serif-stack, size: 13pt, style: "italic", fill: ink)
    #it.body
  ]

  // Figures
  show figure: it => block(spacing: 1.4em)[
    #it.body
    #v(4pt)
    #line(length: 100%, stroke: 0.4pt + rule)
    #v(2pt)
    #set text(font: sans-stack, size: 8.5pt, fill: ink-3)
    #it.caption
  ]

  // Tables
  set table(
    stroke: (x, y) => (
      top:    if y == 0 { 1.5pt + ink } else if y == 1 { 0.6pt + rule-strong } else { 0pt },
      bottom: if y == 0 { 0pt } else { 0.4pt + rule },
    ),
    inset: (x: 8pt, y: 6pt),
  )
  show table.cell.where(y: 0): set text(
    font: sans-stack, size: 8pt, weight: 600, fill: ink-3, tracking: 0.06em
  )

  // ----- Title block -----
  if title != none {
    block[
      #set text(font: sans-stack, size: 8pt, weight: 600, fill: ember, tracking: 0.1em)
      #upper[— Civilytics Research]
    ]
    v(8pt)
    block[
      #set text(font: display-stack, weight: 900, size: 32pt, fill: ink, tracking: -0.035em)
      #set par(leading: 0.4em)
      #title
    ]
    if subtitle != none {
      v(8pt)
      block[
        #set text(font: serif-stack, style: "italic", size: 14pt, fill: ink-2)
        #set par(leading: 0.55em)
        #subtitle
      ]
    }
    v(18pt)
    line(length: 100%, stroke: 3pt + ink)
    v(2pt)
    line(length: 100%, stroke: 0.4pt + rule)
    v(8pt)

    // Authors + date row
    grid(
      columns: (1fr, 1fr),
      align: (left, right),
      [
        #set text(font: sans-stack, size: 7.5pt, fill: ink-3, tracking: 0.08em)
        #upper[Authors] \
        #set text(font: sans-stack, size: 10pt, fill: ink, weight: 500, tracking: 0em)
        #if authors.len() > 0 {
          authors.map(a => if type(a) == str { a } else { a.name }).join(", ")
        }
      ],
      [
        #set text(font: sans-stack, size: 7.5pt, fill: ink-3, tracking: 0.08em)
        #upper[Published] \
        #set text(font: sans-stack, size: 10pt, fill: ink, weight: 500, tracking: 0em)
        #if date != none { date }
      ]
    )
    v(24pt)

    if abstract != none {
      block(
        stroke: (left: 2pt + ember),
        inset: (left: 14pt),
      )[
        #set text(font: serif-stack, style: "italic", size: 12pt, fill: ink)
        #set par(leading: 0.55em)
        #abstract
      ]
      v(20pt)
    }

    if toc {
      block[
        #set text(font: sans-stack, size: 7.5pt, fill: ink-3, tracking: 0.08em)
        #upper[Contents]
      ]
      v(4pt)
      line(length: 100%, stroke: 0.4pt + rule)
      v(8pt)
      outline(title: none, indent: auto, depth: 3)
      v(20pt)
      pagebreak()
    }
  }

  doc
}

// Quarto entry point
#show: doc => civilytics(
  title: $title$,
  $if(subtitle)$subtitle: $subtitle$,$endif$
  $if(by-author)$authors: ($for(by-author)$"$it.name.literal$",$endfor$),$endif$
  $if(date)$date: $date$,$endif$
  $if(abstract)$abstract: [$abstract$],$endif$
  toc: $if(toc)$true$else$false$endif$,
  doc
)

$body$
