--- Convert LaTeX math to inline MathML for the Hugo web build.
--
-- Why: civilytics.com has no math renderer. The obvious fix is to vendor KaTeX,
-- but that means ~300 KB of JS plus ~20 font files committed to the site repo,
-- a Content-Security-Policy amendment, and a client-side render on every visit.
-- Pre-rendering to MathML instead needs none of that: modern browsers render it
-- natively and screen readers read it semantically (better than KaTeX's HTML).
--
-- Pandoc also wraps its output in <semantics> and appends the original LaTeX in
-- an <annotation> element. We strip both -- see to_mathml() for why that markup
-- is actively harmful under Goldmark. Nothing is lost by dropping it: the LaTeX
-- source still lives in white_paper.qmd, and the PDF typesets from that source
-- through LaTeX rather than through this filter.
--
-- Only applied to the hugo-md build. The PDF renders math through LaTeX as
-- usual, and the standalone HTML keeps whatever Quarto's default method is.

local function to_mathml(el)
  local doc = pandoc.Pandoc({ pandoc.Plain({ el }) })
  local ok, html = pcall(pandoc.write, doc, "html", { html_math_method = "mathml" })
  if not ok or not html then
    -- Leave the node untouched rather than silently dropping an equation.
    io.stderr:write("mathml.lua: could not convert math, leaving as LaTeX\n")
    return nil
  end
  -- Goldmark runs its inline parser over any text inside the raw HTML we emit,
  -- and rewrites the LaTeX in <annotation> -- an underscore flanked by
  -- punctuation (`}_{`) opens emphasis, so it injects <em>. <em> is on the
  -- HTML parser's MathML breakout list, so the browser then closes <math>
  -- early and renders the rest of the annotation as visible text. Dropping the
  -- annotation removes the only markdown-visible text inside the element.
  -- <semantics> exists only to pair the presentation markup with that
  -- annotation, so it goes too; <math><mtable>...</mtable></math> on its own is
  -- valid presentation MathML.
  html = html:gsub('<annotation encoding="application/x%-tex">.-</annotation>', "")
  html = html:gsub("</?semantics>", "")
  return (html:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Math(el)
  local html = to_mathml(el)
  if not html then return nil end
  if el.mathtype == "DisplayMath" then
    -- Goldmark needs a blank line around block-level raw HTML to avoid
    -- wrapping it in a stray paragraph.
    return pandoc.RawInline("html", "\n\n" .. html .. "\n\n")
  end
  return pandoc.RawInline("html", html)
end
