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
#
# ★ THE SET IS A FUNCTION AND IS EXPOSED BY NAME so a consumer can EXTEND it. It is deliberately
# not reachable for removal: `programs.mdformat.plugins` is a REPLACING option, so a consumer
# who writes `plugins = p: [ p.mdformat-gfm ]` meaning to add gfm silently drops all three of
# these and nothing reports it. Making the base unreachable through the extension point means a
# consumer cannot express that mistake — absence of a declaration yields the invariant rather
# than its negation.
#
# ★ WHAT IS NOT HERE, and why the omissions are decisions:
#   · gfm       — measured destructive on real tables; genuinely per-corpus, which is what the
#                 `extraPlugins` extension point exists for.
#   · beautysh  — rejected on two independent grounds: it reports `ERROR` while exiting 0, which
#                 is the silent-failure class this repair removes, and it transitively enables
#                 gfm through its dependency edge.
p: [
  p.mdformat-footnote
  p.mdformat-frontmatter
  p.mdformat-simple-breaks
]
