# THE BASE MDFORMAT PLUGIN SET — the representational invariants of markdown this ecosystem
# defends, in one place because it has three call sites and drift across them is what produced
# the defect this file repairs.
#
# Each member answers a question about what a construct MEANS, not how it should look:
#   · frontmatter    — a leading `---` block is STRUCTURED DATA. Without it mdformat reads that
#                      block as a thematic break followed by a heading and rewrites it. One
#                      repository's frontmatter was destroyed exactly that way, and the gate
#                      stayed green afterwards because the damage is idempotent.
#   · footnote       — a `[^1]:` line is a FOOTNOTE DEFINITION. Without it mdformat escapes the
#                      construct. Measured protective rather than cosmetic.
#   · simple-breaks  — a thematic break renders as `---` rather than the underscore run.
#   · gfm            — a `|`-delimited row is a TABLE ROW. Without it the row is ordinary prose,
#                      in which `\|` is a redundant escape mdformat normalises away — so a cell
#                      holding a literal pipe silently becomes several cells the next time the
#                      document is rendered. Measured on a real row: 2 cells against a 2-column
#                      header became 5. This ecosystem's markdown is read as GitHub-flavoured
#                      markdown, which is what makes the escape required rather than decorative.
#
# ★ THE SET IS A FUNCTION AND IS EXPOSED BY NAME so a consumer can EXTEND it. It is deliberately
# not reachable for removal: `programs.mdformat.plugins` is a REPLACING option, so a consumer
# who writes `plugins = p: [ p.mdformat-gfm ]` meaning to add one plugin silently drops the rest
# of these and nothing reports it. Making the base unreachable through the extension point means a
# consumer cannot express that mistake — absence of a declaration yields the invariant rather
# than its negation.
#
# ★ WHAT IS NOT HERE, and why the omission is a decision:
#   · beautysh  — it reports `ERROR` while exiting 0, which is the silent-failure class this
#                 repair removes. That ground is independent of gfm's disposition: it rejected
#                 beautysh while gfm was excluded and rejects it now that gfm is a member, so
#                 beautysh does not arrive on gfm's dependency edge.
p: [
  p.mdformat-footnote
  p.mdformat-frontmatter
  p.mdformat-gfm
  p.mdformat-simple-breaks
]
