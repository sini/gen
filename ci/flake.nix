{
  inputs = {
    # ── THE HUB ITSELF — and the ONLY route to a sibling library ── is NOT an input.
    # This subflake declares no sibling pin and no `gen` input. It reaches the root flake as `gen`,
    # bound in `outputs` below by `builtins.getFlake` of `self.sourceInfo` at its own `narHash`: the
    # working tree under test, with the root flake's inputs resolved from the ROOT `flake.lock`.
    #
    # ★ WHY NOT `gen.url = "path:.."`, which is what this was. Lix refuses a relative `path` node in a
    # lock (`lock file contains mutable lock`), so the whole plane was red under Lix before a check
    # ran; and a Lix-written `path:..?narHash=…` lock pins a STALE SNAPSHOT of the tree, a published
    # copy of itself (den-hoag-lbtnv D1). Re-declaring the 21 siblings here instead is the majority
    # form elsewhere and the REJECTED one here: it reverses den-hoag-erls and gives the hub two
    # independent pin sets for one edge.
    #
    # ★ AND IT IS ONE PIN SET, NOT A ROOT LOCK AND A CI COPY OF IT. Through `gen.inputs.gen-X` every
    # sibling is reached at the ROOT lock's pin, which is what a consumer resolves: the PURE side of
    # the byte-parity oracle, the perf bench's src set and the published `gen.lib.mkGenLibs` surface
    # are one build of each library. The `path:..` form held a COPY of the root's pins in this lock,
    # snapshotted at ci lock time, and `lock-agreement` gated that copy; with no copy the property it
    # gated holds by construction and the cell is retired. `ci-declares-no-member` refuses a `gen` or
    # roster-member input being re-added here, which is the one act that would re-form the copy.

    # ── THE CI HARNESS — the machinery this gate is built from, now consumed rather than copied ──
    # gen-harness is the extraction of ci from this repository. Until now the hub kept its own copy
    # of the shared gate machinery, because the hub is not an mkCi consumer (see the pre-commit
    # block below) and the surface it needed was file layout rather than declared outputs. The copy
    # bought nothing but drift: the same repair was authored twice on four separate days, three of
    # those pairs carrying the same commit subject verbatim, and twice the second copy went stale
    # in prose while the first was fixed.
    #
    # THE TRADE, taken deliberately: this gate gains one external pin, so if gen-harness breaks the
    # hub's gate breaks with it, and a lock bump joins every harness-surface change. No cycle
    # re-opens — gen-harness declares eight inputs and all eight are tools, by construction and by
    # its own acceptance test, so this is a leaf rather than a back edge.
    #
    # The follows lines below are the whole overlap of the two input sets (six of them); without
    # them each shared tool would appear twice in this lock. gen-harness's remaining two inputs
    # (nix-unit, import-tree) serve mkCi, which this flake does not call — they arrive in the lock
    # and are never evaluated.
    gen-harness.url = "github:sini/gen-harness";
    gen-harness.inputs.nixpkgs.follows = "nixpkgs";
    gen-harness.inputs.flake-parts.follows = "flake-parts";
    gen-harness.inputs.flake-root.follows = "flake-root";
    gen-harness.inputs.treefmt-nix.follows = "treefmt-nix";
    gen-harness.inputs.devshell.follows = "devshell";
    gen-harness.inputs.git-hooks-nix.follows = "git-hooks-nix";

    # ── REFERENCE side (frozen golden nixpkgs stack) for the re-host parity oracle ──
    # ORIGINAL nixpkgs-signature gen-schema (`{ lib, algebra }`), pinned to its pre-re-host rev (the
    # last commit before the pure re-host changed the signature). A PERMANENT golden-reference pin
    # (same class as the nixpkgs-lib / flake-parts pins below), NEVER a release-set pin — do NOT sweep
    # it forward to main. main carries the pure re-host signature (`{ prelude, merge, algebra }`) the
    # oracle's reference side cannot call: rotating it to main makes rehost-den-parity throw (`called
    # without required argument 'merge'`) and dissolves the frozen witness the check exists to compare
    # re-host(main) against.
    #
    # A frozen reference is only sound where the SUBJECT's grammar is stable. The registry/schema
    # surface this pin guards is; the aspect grammar is not — it moves by design ruling, so no frozen
    # aspect reference can track it and a parity gate built on one reds on every ruled improvement
    # rather than on a defect. That is why only the schema half of the golden pair survives here.
    #
    # ★ AND THE SAME PRECONDITION HAS SINCE FAILED ON ONE AXIS OF THE SURVIVING HALF: the IDENTITY
    # ENCODING. gen-schema `75d40c1` re-minted `id_hash` by design ruling (ADR-0016) — the kind left
    # the digest for a `"<kind>:"` tag and the preimage became `toJSON` of the ⟨label,value⟩ pairs —
    # so the frozen witness reds on a ruled improvement here exactly as it would on the aspect
    # grammar, and no forward golden pin can carry the new encoding because every nixpkgs-signature
    # revision predates it. The identity axis is therefore EXCLUDED from the comparison: the parity
    # arms restate over instance key sets and every non-identity field (which do still hold
    # byte-for-byte), and `id_hash` is held by a teeth arm on the PURE engine instead of against the
    # frozen witness. ci/rehost-den-parity.nix states the exclusion and the arm at the arms.
    gen-schema-orig.url = "github:sini/gen-schema/2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6";
    # nixpkgs LIB ONLY — the reference `lib.evalModules` engine. Ecosystem policy: pull the pinned
    # nixpkgs.lib (auto-generated per nixpkgs release), NOT full nixpkgs, where only `lib.*` is needed.
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib/db3f255737b94216eb71cce308e2912cf6bc2d7c";

    # nixpkgs is the RUNNER only (treefmt, runCommand check derivations) — full nixpkgs required.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    ciInputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      # The ROOT flake at this tree's own source and narHash (see the header). The context discard
      # is required, not cosmetic: without it upstream Nix and Lix refuse a store-path reference in a
      # flake ref; without the `narHash` all three evaluators refuse an unlocked ref in pure mode.
      # `self.sourceInfo` carries a `narHash` clean and dirty under all three, so an uncommitted edit
      # is seen here exactly as `path:..` saw it (driven, den-hoag-lbtnv D1).
      gen = builtins.getFlake (
        builtins.unsafeDiscardStringContext "path:${self.sourceInfo.outPath}?narHash=${self.sourceInfo.narHash}"
      );
      inputs = ciInputs // {
        inherit gen;
      };
      inherit (nixpkgs) lib;

      # The root flake's own inputs — the sibling route. No sibling revision is written in THIS FILE,
      # and `nix flake update gen-X` here reports that no such input exists.
      #
      # ★ THE VALUE IS THE ROOT'S PIN BY REFERENCE: `gen` resolves its inputs from the root
      # `flake.lock`, so a root pin bump moves every check below in the same commit, with no ci act.
      genInputs = inputs.gen.inputs;

      # ── re-host byte-parity oracle (permanent regression) ──
      # PURE side tracks the published re-host mains; REFERENCE side is the frozen original
      # nixpkgs-signature gen-schema driven through the pinned nixpkgs.lib. A future gen-merge /
      # re-host change that breaks byte-parity on the instance key sets or on any non-identity field
      # makes this check fail. The `id_hash` is the one excluded axis (see the golden pin above) and
      # is held by `teeth-mutation-pure` on the pure engine, which ships its own seeded control.
      denParity = import ./rehost-den-parity.nix {
        inherit (genInputs)
          gen-prelude
          gen-identity
          gen-types
          gen-merge
          gen-memo
          gen-scope
          gen-algebra
          gen-schema
          ;
        inherit (inputs) gen-schema-orig;
        lib = inputs.nixpkgs-lib.lib;
      };

      # Keys that MUST be `true` for parity to hold (the regression gate).
      denParityKeys = [
        "parity-schema"
        "parity-instances"
        "both-evaluated"
        "teeth-mutation"
        "teeth-mutation-pure"
        "arming-teeth-mutation-pure"
        "teeth-parity"
        "parity-nested"
      ];

      # ── mkGenLibs wiring smoke check ──
      # Forces every key of the hub's published `gen.lib.mkGenLibs` so a broken lib wiring (bad pin
      # bump, drifted `.lib` signature) or a roster drift fails `nix flake check ./ci`. It also holds
      # the stratum partition: total declaration, published buckets matching it, and each bucket
      # entry the same value as its flat member, and the published EXPORT SURFACE: each member's
      # published names fingerprinted against a hand-maintained pin, so a pin bump that CHANGES what
      # a member publishes reddens as well as one that breaks it. `.gate` is the per-key wiring-ok
      # record + the roster, stratum and surface tripwires; `.gateKeys` the keys that MUST be `true`.
      mkGenLibsEval = import ./mkgenlibs-eval.nix { inherit (inputs) gen; };

      # ── agents-md-hub-inputs — the AGENTS.md hub sheet, CI-bound (den-hoag-bzcb4, den-hoag-0mjo7) ──
      # Reads every roster projection AGENTS.md carries back out of the committed file — the fenced
      # gen-input enumeration, the roster region (concern rows, retired and sibling registers), the
      # stratum assignment and the Drift-check record, each a marker-declared window — and compares
      # each against the flake: the input set (`genInputs`, filtered by prefix, both directions), each
      # member's `flake.nix` description, `(gen.lib.mkGenLibs { }).strata` and the root flake's own
      # shape; outside the windows every `gen-*` name must be live or registered. So a new hub input,
      # a retirement or a stale record reddens this instead of leaving the sheet to rot silently the
      # way it did once (den-hoag-8j5b, 19-vs-21; six unbound copies at den-hoag-0mjo7). Takes `gen`
      # for the roster of record and the root shape, as `mkgenlibs-eval.nix` does. `.gate`/`.gateKeys`
      # follow the same shape as every other check below.
      hubInputSheet = import ./agents-md-hub-inputs.nix {
        inherit genInputs lib;
        inherit (inputs) gen;
      };

      # ── inject-payload — the permanent O-INJ-2 cell ──
      # Asserts the MEASURED ADR-0023 (b) ground the crossing's `injectAdapter` declares: a real
      # `lib.compose` payload still reaches a function transitively (the schema sub-tree's gen
      # types), with the plain-clean and planted-caught controls in the same run. If a schema
      # change flips the predicate, this fails and the ADR-0023 disposition re-opens by
      # construction. `.gate` is the per-key record; `.gateKeys` the keys that MUST be `true`.
      injectPayload = import ./inject-payload.nix { inherit (inputs) gen; };

      # ── declared-content — the PERMANENT cell over the hub's DELIVERY-CLASS PROJECTION ──────
      # ADR-0028's Rider on BOTH measured arms: the contentless class (den-hoag-jwm8) and the
      # wrong-category channel (den-hoag-t3q9). Drives `genDelivery.project`/`realize` with the REAL
      # pinned `gen.lib.mkGenLibs` roster, wired the way `flakeModules/default.nix` wires it — the
      # exact composition a consumer of this hub gets — plus a lexical arm over the shipped module
      # source, because the hub's CALL SITE is a path no gate here otherwise evaluates.
      # `.gate` is the per-key record; `.gateKeys` the keys that MUST be `true`.
      declaredContent = import ./declared-content.nix { inherit (inputs) gen; };

      # ── direction-of-dependence lint ──
      # ADR-0015's enforcement half: no roster member may declare an input on a HIGHER stratum than
      # its own, under the chain substrate < modules < aspects < framework, save the closed
      # two-edge exception ruled 2026-08-18 (which is printed entry by entry, with its cause and
      # its retirement carrier, on every run). The observable is the DECLARED root-flake input
      # NAME — never a revision, so the lock graph ADR-0015 forbids as the enforcement source is
      # not what this reads. Like the check above it governs the hub's PINNED revisions, which is
      # the surface consumers get. `.gate` is the per-arm record incl. the in-tree arming; the
      # failure it guards is silent, so `refused: 0` travels with controls that fire in the same
      # run.
      directionOfDependence = import ./direction-of-dependence.nix { inherit (inputs) gen; };

      # ── architecture-library-graph — ARCHITECTURE.md's library graph, CI-bound ──
      # The document's figures are hand-written and the failure is silent: prose does not evaluate,
      # so a member joining or leaving the roster leaves the picture exactly as it was, and that is
      # how a retired library came to stand as live in it and a roster enumeration came to run one
      # member short. This reads the marker-delimited mermaid block back out of the committed file
      # and compares it, both directions, against the roster of record (`gen.lib.mkGenLibs`, the same
      # value `mkgenlibs-eval.nix` gates) for the NODES and against each member's own declared
      # root-flake input names for the EDGES — the same observable `direction-of-dependence.nix`
      # reads, so no revision is read here either. `.gate`/`.gateKeys` follow the shape above.
      architectureLibraryGraph = import ./architecture-library-graph.nix {
        inherit (inputs) gen;
        inherit lib;
      };

      # ── readme-figures — README.md's spelled-out roster-count figures, CI-bound ──
      # Five prose sentences state "N of the M roster libraries/members/flakes/repos" against the
      # roster, and every one drifted the same way the architecture diagram above did — silently,
      # because prose does not evaluate — while sitting in the one form (spelled-out words) every
      # digit-anchored figure oracle in this ecosystem is blind to (den-hoag-hub-readme-roster-count-
      # words-k4ufw). This reads each sentence's now-digit figure back out of the committed file and
      # compares it against the roster of record and against each member's own tree (a purity
      # scanner under `ci/tests/`, a declared `.lib` output, `gen-harness.lib.mkCi` plus a GitHub
      # Actions workflow, an `AGENTS.md` sheet) at CI's pin. `.gate`/`.gateKeys` follow the shape
      # above.
      readmeFigures = import ./readme-figures.nix {
        inherit (inputs) gen;
        inherit genInputs lib;
      };

      # ── sole-evaluator scan ──
      # ADR-0006's enforcement half, and readiness-bar term T2(a)'s instrument: gen-scope is the
      # sole evaluator, so no other tree in the scanned domain — the roster read by evaluation,
      # plus the hub — may exhibit an evaluation-driving construct. The ruled DOMAIN is a property
      # ("anything that evaluates, wherever hosted"), which is not statically decidable, so the
      # criterion UNDER-approximates it and the check says so on every run: a green is a statement
      # about the instrument's reach, never about the property. `domain-total` is the tripwire — the
      # roster ENUMERATES and `ci/flake.lock` NOTIFIES, so a tree the walk would be blind to is red
      # rather than absent. `.gate` is the per-arm record incl. the in-tree arming.
      #
      # `hubSource` is `self.sourceInfo.outPath` — the git source, the tree the flake publishes.
      # Measured when the hub entered this lock as `path:..`: that fetcher copied the raw directory
      # (`.git`, `.direnv`, `result` symlinks, any `.worktrees/` checkout), so the scan's population
      # moved with a developer's local state. Same value, and the same reason, as the
      # `agents-md-citations` wiring below.
      soleEvaluator = import ./sole-evaluator.nix {
        inherit (inputs) gen;
        inherit lib;
        hubSource = self.sourceInfo.outPath;
      };

      # ── pin-coherence — L7 ──
      # This compares ONE edge class across TWENTY-ONE repositories — every roster member's
      # `ci/flake.lock`, reached at the revision this hub pins. Under the module-layout pattern's L1
      # a library defaults each dependency out of its own ci lock, so incoherent pins split one
      # dependency into several store paths on the flakeless path and `import` stops memoising.
      # `.gate` is the per-arm record incl. the in-cell arming; `.gateKeys` the keys that MUST be
      # `true`. It takes `gen` for the ROSTER and for the 21 member trees.
      pinCoherence = import ./pin-coherence.nix {
        inherit (inputs) gen;
        inherit lib;
      };

      # ── hub-entry — L4, and it is the only check here that reads `../default.nix` at all ──
      # `pin-coherence` is about PINS; this is about WIRING — which members
      # the hub's standalone entry declares, and which repository each default points at. It takes
      # `gen` for the roster of record and for the entry itself, and reads `./flake.lock` as data.
      # `.gate` is the per-arm record incl. the in-cell arming; `.gateKeys` the keys that MUST be
      # `true`.
      hubEntry = import ./hub-entry.nix {
        inherit (inputs) gen;
        inherit lib;
      };

      # ── ci-declares-no-member — the one act that would re-form a ci copy of the pins ──
      # A `gen` or roster-member input declared in THIS flake. `.gate` is the per-arm record incl.
      # the in-cell arming; `.gateKeys` the keys that MUST be `true`.
      ciDeclaresNoMember = import ./ci-declares-no-member.nix {
        inherit (inputs) gen;
        inherit lib;
      };

      # ── hub-entry-agreement — the two entry paths answer one query alike ──
      # `hub-entry` reads the standalone entry's WIRING hermetically; this FORCES both entry paths on
      # gen-inspect's published fleet and compares the answers, so it fetches and is kept apart.
      # `.gate` is the per-arm record incl. the in-cell arming; `.gateKeys` the keys that MUST be
      # `true`.
      hubEntryAgreement = import ./hub-entry-agreement.nix { inherit (inputs) gen; };

      # The compose-parity oracle (den-hoag-i34de): warm ≡ cold through `gen.lib.compose`, at the
      # root lock's gen-merge and gen-memo. `.gate` is the per-cell record; `.overflowPin` is the one
      # cell whose green is an uncatchable abort, read by the `checks` job (see the file header).
      composeParity = import ./compose-parity.nix { inherit (inputs) gen; };

      # L3: the substrate the hub hands the three roster members whose flake `.lib` is published
      # unapplied. `.gate` is the per-arm record incl. the in-cell arming; `.gateKeys` the keys that
      # MUST be `true`.
      hubSubstrate = import ./hub-substrate.nix {
        inherit (inputs) gen;
        inherit genInputs lib;
      };

      # The same value `gen-harness`'s own flake module installs for its twenty-two consumers. The
      # comment above this treefmt block says the set here may not be trimmed below the one
      # consumers receive; reading it from the harness makes that hold by construction, across the
      # repository boundary, rather than by two lists kept in agreement by hand.
      #
      # `{ names, plugins }`: the membership fact and the `programs.mdformat.plugins` value built
      # from it. The guard below is handed the names from here rather than restating them.
      mdformatBase = inputs.gen-harness.lib.mdformatBasePlugins;
      mdformatBasePlugins = mdformatBase.plugins;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = lib.systems.flakeExposed;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
        inputs.flake-root.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];

      # Raw oracle results (system-independent, pure eval) for eyeballing:
      #   nix eval ./ci#lib.parity.den      --json | jq
      #   nix eval ./ci#lib.mkGenLibsEval   --json | jq   (keyCount / missing / extra / strata / per-key gate)
      flake.lib.parity = {
        den = denParity;
      };
      flake.lib.mkGenLibsEval = mkGenLibsEval;
      #   nix eval ./ci#lib.hubInputSheet --json | jq
      flake.lib.hubInputSheet = hubInputSheet;
      #   nix eval ./ci#lib.injectPayload.gate --json | jq
      flake.lib.injectPayload = injectPayload;
      #   nix eval ./ci#lib.declaredContent.gate --json | jq
      flake.lib.declaredContent = declaredContent;
      #   nix eval ./ci#lib.direction.report --json | jq
      flake.lib.direction = directionOfDependence;
      #   nix eval ./ci#lib.soleEvaluator.report --json | jq
      flake.lib.soleEvaluator = soleEvaluator;
      #   nix eval ./ci#lib.ciDeclaresNoMember.report --json | jq
      flake.lib.ciDeclaresNoMember = ciDeclaresNoMember;
      #   nix eval ./ci#lib.pinCoherence.report --json | jq   (rows / incoherent / arming)
      flake.lib.pinCoherence = pinCoherence;
      #   nix eval ./ci#lib.hubEntry.report --json | jq   (rows / misdirected / arming)
      flake.lib.hubEntry = hubEntry;
      #   nix eval ./ci#lib.hubEntryAgreement.report --json | jq   (answers / arming)
      flake.lib.hubEntryAgreement = hubEntryAgreement;
      #   nix eval ./ci#lib.hubSubstrate.report --json | jq   (rows / underSupplied / text / arming)
      flake.lib.hubSubstrate = hubSubstrate;
      #   nix eval ./ci#lib.architectureLibraryGraph.report --json | jq
      flake.lib.architectureLibraryGraph = architectureLibraryGraph;
      #   nix eval ./ci#lib.composeParity.gate --json | jq
      flake.lib.composeParity = composeParity;

      perSystem =
        {
          self',
          config,
          pkgs,
          system,
          ...
        }:
        let
          # Build a check derivation: prints the oracle result (incl id_hash sample + teeth), and
          # FAILS the build if any required key is not `true` — a permanent byte-parity regression.
          mkParityCheck =
            name: result: keys:
            let
              gate = lib.genAttrs keys (k: result.${k});
              allOk = builtins.all (k: result.${k} == true) keys;
              report = builtins.toJSON {
                inherit allOk;
                results = gate;
                sample = result.sample or { };
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "PARITY REGRESSION — re-host is no longer byte-identical to the nixpkgs stack" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the mkGenLibs wiring check: prints the per-key gate (+ the roster and stratum
          # diffs, and the arming) and FAILS the build if any key failed to evaluate, the roster
          # drifted, the stratum partition is not total and in agreement with the flat roster, or an
          # `arming-*` arm stopped firing (mkgenlibs-eval.nix). The roster of record is that file,
          # never a count. A failing arm is either the surface pin refusing or the comparison behind
          # it having gone blind; both are red, because a guard that can no longer refuse is not a
          # passing guard.
          mkGenLibsCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                inherit (g)
                  keyCount
                  memberCount
                  keys
                  missing
                  extra
                  strata
                  strataMissing
                  strataExtra
                  strataUnknown
                  bucketCounts
                  bucketMismatch
                  bucketOverlap
                  resolveFailed
                  agreeFailed
                  retirementFailed
                  retirementRegister
                  surfaceHash
                  surfaceDrift
                  surfaceDriftNames
                  arming
                  pinDomain
                  ;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "mkGenLibs WIRING REGRESSION — a lib key failed to evaluate, the roster drifted, or the stratum partition broke" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the agents-md-hub-inputs check: prints the documented/actual roster, every
          # window's diff against the flake (missing/extra inputs; concern rows missing, extra, with
          # a drifted repo or description; retired or sibling rows that are live; unregistered
          # `gen-*` names and backticked retired keys in live context; unknown table rows; the
          # recorded and actual Drift-check JSON and stratum assignment) and FAILS the build if any
          # gate key is not `true`.
          mkHubInputSheetCheck =
            name: h:
            let
              allOk = builtins.all (k: h.gate.${k} == true) h.gateKeys;
              failed = builtins.filter (k: h.gate.${k} != true) h.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                inherit (h)
                  documented
                  actual
                  missing
                  extra
                  concernMissing
                  concernExtra
                  concernRepoDrift
                  concernDescDrift
                  retiredStillLive
                  siblingStillLive
                  unregistered
                  retiredInLiveContext
                  unknownRows
                  driftDocumented
                  driftActual
                  strataDocumented
                  strataActual
                  ;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "AGENTS.md HUB SHEET DRIFT — a bound window (inputs block, roster region, stratum assignment, Drift-check record) or the live context no longer agrees with the flake; the failed keys and the offending names are in the report above" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the direction-of-dependence check: prints the full report — the class tallies,
          # every edge a reader must act on (refused, excepted, unranked, off-roster), the
          # exception entry by entry with its cause and carrier, and the arming — and FAILS the
          # build if any gate arm is not `true`. A failing arm is either an upward edge (the lint
          # firing) or an arming arm that stopped firing (the lint gone blind); both are red,
          # because a guard that can no longer refuse is not a passing guard.
          mkDirectionCheck =
            name: d:
            let
              allOk = builtins.all (k: d.gate.${k} == true) d.gateKeys;
              failed = builtins.filter (k: d.gate.${k} != true) d.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // d.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "DIRECTION OF DEPENDENCE — a roster member declares an input above its own stratum, or the guard's own arming stopped firing" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the architecture-library-graph check: prints the full report — the roster, the
          # nodes the diagram declares live and retired, and every name or edge a reader must act on
          # — and FAILS the build if any gate arm is not `true`. A failing arm names the offending
          # member or edge in `missing`/`extra`/`mismarked`/`edgesMissing`/`edgesExtra`/`unclassified`,
          # so the remedy is the diagram line to add or delete rather than a denial. The oracle's
          # cardinality travels with it — `classifiedLineCount` short of `expectedLineCount` is how an
          # unparsed line would otherwise read as a clean absence.
          mkArchitectureGraphCheck =
            name: a:
            let
              allOk = builtins.all (k: a.gate.${k} == true) a.gateKeys;
              failed = builtins.filter (k: a.gate.${k} != true) a.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // a.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "ARCHITECTURE.md LIBRARY GRAPH DRIFT — the diagram carries a line the check cannot classify, or no longer matches the roster of record or the members' declared inputs" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the readme-figures check: prints the full report — the roster size, the members
          # missing each carried property, and every sentence whose digits disagree with the live
          # count or whose pattern no longer matches the shipped file — and FAILS the build if any
          # gate arm is not `true`. A failing arm names the offending sentence in `disagreeing`, the
          # offending pattern in `unreached`, or the offending member in one of the `*Missing` lists,
          # so the remedy is the number or the member to fix rather than a denial.
          mkReadmeFiguresCheck =
            name: r:
            let
              allOk = builtins.all (k: r.gate.${k} == true) r.gateKeys;
              failed = builtins.filter (k: r.gate.${k} != true) r.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // r.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "README.md ROSTER-COUNT FIGURE DRIFT — a sentence's digits no longer match the live roster or a member's own tree, or the scan itself stopped reaching a sentence" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the sole-evaluator REPORT: prints the full report — the class tallies, every tree a
          # reader must act on named with the FILE AND LINE of each match, the three ruled entry
          # sets entry by entry with their causes and carriers, the per-tree read/excluded counts
          # and the arming — and names every gate arm that is not `true`. The scan, its criterion,
          # its exception sets and its arming are untouched; only the DISPOSITION of a refusal is.
          #
          # ★★★ AN APP, AND NOT A `checks` DERIVATION (den-hoag-6fmmb, owner-ruled 2026-09-13):
          # **a check whose red is cleared by a RULING must not gate; one cleared by a FIX should.**
          # A refusal here is the ruled property being TRUE of a tree — it is disposed of by an
          # exception entry or by the reading standing, both of them owner acts, so nothing a
          # builder can do clears it. Wired as a gate it took this hub to thirty-three consecutive
          # red runs over six days and destroyed the signal of the fourteen cells beside it; a tree
          # that is always red gates nothing. The property survives and is verified by audit at the
          # consolidation milestones (`den-hoag-0pk67`).
          #
          # ★ AN APP RATHER THAN A NON-FAILING CHECK, because nix HIDES A BUILDER'S LOG AT EXIT 0
          # (the hub's standing Q6): a `runCommand` that stopped exiting 1 would stop being read at
          # all, trading a false red for a silence. `nix run` executes a PROGRAM, whose stdout
          # reaches the job log on every run — the same shape `perf-bench`, `flake-compare` and
          # `fleet-consistency` already use, and CI runs it as its own workflow job.
          #
          # ★ An EVALUATION failure of this app still reds its job, and that is correct under the
          # same rule: a scan that cannot run is an instrument defect, cleared by a fix.
          # ★ den-hoag-0pk67 unit-c-instruments-build — `arming-sound` (`ci/sole-evaluator.nix`) IS
          # THE ONE PURE-ARMING GATE KEY. O1..O10 conjoin a live reading with their own arming by
          # design (the comment above `gate` in that file), so `failed` cannot be partitioned by
          # exclusion into arming and reading keys — every OTHER key mixes a
          # ruling-cleared reading into the same boolean. `arming-sound` alone is fix-cleared: it is
          # false only when a SEEDED plant stopped being caught, never when the live corpus turns up
          # a real refusal. den-hoag-6fmmb binds both halves of this: a reading cleared by a ruling
          # must not gate (readingFailed, below, never does); a check cleared by a fix should
          # (armingFailed does).
          mkSoleEvaluatorReport =
            name: s:
            let
              allOk = builtins.all (k: s.gate.${k} == true) s.gateKeys;
              failed = builtins.filter (k: s.gate.${k} != true) s.gateKeys;
              armingFailed = builtins.filter (k: k == "arming-sound") failed;
              readingFailed = builtins.filter (k: k != "arming-sound") failed;
              gating = armingFailed != [ ];
              report = builtins.toJSON ({ inherit allOk failed; } // s.report);
              reportFile = pkgs.writeText "${name}-report.json" report;
            in
            pkgs.writeShellApplication {
              name = "gen-${name}-report";
              runtimeInputs = [ pkgs.coreutils ];
              # Everything on stdout: the refusal sentence is a continuation of the report a reader
              # meets, and a stderr limb would be free to interleave ahead of it in the job log.
              text = ''
                echo "── ${name} ──"
                cat ${reportFile}
                echo
                ${lib.optionalString (readingFailed != [ ]) ''
                  echo "SOLE EVALUATOR — a tree in the scanned domain exhibits an evaluation construct outside gen-scope, or the scan's own arming stopped firing. A refusal is the RULED PROPERTY being true of that tree: it is disposed of by an exception entry carrying a cause and a carrier, or by the reading standing — NEVER by narrowing the criterion until the tree passes"
                  echo "REPORTED, GATED BY NOTHING (den-hoag-6fmmb): the arms above are cleared by a RULING, not by a fix, so this does not fail CI. Read it, do not ignore it."
                ''}
                ${lib.optionalString gating ''
                  echo "SOLE EVALUATOR ARMING — a seeded plant this scan exists to catch went uncaught, or a seeded self-test stopped discriminating: ${lib.concatStringsSep " " armingFailed}. Read report.arming above: each sub-arm is a seeded reading compared against its expectation, printed beside the reading it arms. Disposed of by a FIX to the scan itself, never by a ruling."
                ''}
                ${lib.optionalString gating "exit 1"}
              '';
            };
          # Build the hub-entry check (L4): prints the entry's own member-to-path map with the node
          # and repository each path resolves to, and names any member wired to another repository.
          #
          # GATING, unlike `pin-coherence`'s two readings. Those readings are observe-only because
          # the states they describe are TRUE of the ecosystem today and not satisfiable by this
          # repository alone (den-hoag-6fmmb). This one is a property of a file in THIS repository,
          # it holds now, and nothing outside the hub has to move for it to keep holding.
          mkHubEntryCheck =
            name: s:
            let
              allOk = builtins.all (k: s.gate.${k} == true) s.gateKeys;
              failed = builtins.filter (k: s.gate.${k} != true) s.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // s.report);
              rowLine =
                r:
                "    ${r.member}: ${builtins.concatStringsSep "/" r.segs}"
                + " => node ${if r.node == null then "<unresolvable>" else r.node}"
                + " => repo ${if r.repo == null then "<none>" else r.repo}"
                + " (expected ${r.expected})";
              badRows = builtins.filter (
                r: builtins.elem r.member (s.report.misdirected ++ s.report.unresolvable)
              ) s.report.rows;
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "-- ${name} --"
                cat "$reportPath"
                echo
                echo "POPULATION: ${toString s.report.memberCount} members wired by the hub entry, ${toString s.report.resolvedCount} resolvable, ${toString s.report.correctCount} resolving to a node of their own repository."
                ${lib.optionalString (badRows != [ ]) ''
                  echo "HUB ENTRY WIRING -- a member's default resolves to a node of the WRONG repository, or to no node at all. import memoises by store path, so a mis-pointed default yields a real, resolvable, wrong library rather than an error (spec S2, L4):" >&2
                  ${lib.concatMapStringsSep "\n" (r: "echo ${lib.escapeShellArg (rowLine r)} >&2") badRows}
                  echo "Disposed of by correcting the path in ../default.nix -- NEVER by narrowing this cell's domain, which is the roster of record." >&2
                ''}
                ${lib.optionalString (failed != [ ]) ''
                  echo "HUB ENTRY -- readings that did not hold: ${lib.concatStringsSep " " failed}. Read report.arming above: every arm is a DELTA against the live reading, printed beside it" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the hub-entry-agreement check: prints both entry paths' answers and each seeded
          # arm's, GATING for the same reason `mkHubEntryCheck` does — a property of this tree.
          mkHubEntryAgreementCheck =
            name: s:
            let
              failed = builtins.filter (k: s.gate.${k} != true) s.gateKeys;
              report = builtins.toJSON ({ inherit failed; } // s.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "-- ${name} --"
                cat "$reportPath"
                echo
                ${lib.optionalString (failed != [ ]) ''
                  echo "HUB ENTRY PATHS DISAGREE -- readings that did not hold: ${lib.concatStringsSep " " failed}. Read report.answers and report.arming above" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the hub-substrate check (L3): prints the substrate `./lib/hubSubstrate.nix` supplies
          # against the live demand of the three unapplied members, and the flake.nix text-arm's C/B/L
          # reading, GATING for the same reason `mkHubEntryCheck` does — this is a property of files in
          # THIS repository, true now, with nothing outside the hub to move for it to keep holding.
          mkHubSubstrateCheck =
            name: s:
            let
              allOk = builtins.all (k: s.gate.${k} == true) s.gateKeys;
              failed = builtins.filter (k: s.gate.${k} != true) s.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // s.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "-- ${name} --"
                cat "$reportPath"
                echo
                echo "TEXT ARM: C=${toString s.report.text.c} B=${toString s.report.text.b} L=${toString s.report.text.l} (need C==1, B==1, L>=18)"
                ${lib.optionalString (s.report.underSupplied != [ ]) ''
                  echo "HUB SUBSTRATE -- a member demands a substrate key ./lib/hubSubstrate.nix does not supply:" >&2
                  ${lib.concatMapStringsSep "\n" (
                    r:
                    "echo ${lib.escapeShellArg "    ${r.member}: missing ${builtins.concatStringsSep ", " r.underSupplied}"} >&2"
                  ) s.report.underSupplied}
                ''}
                ${lib.optionalString (failed != [ ]) ''
                  echo "HUB SUBSTRATE -- readings that did not hold: ${lib.concatStringsSep " " failed}. Read report.arming above: every arm is a DELTA against the live reading, printed beside it" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the pin-coherence check (L7): prints the per-node census across the 21 members'
          # ci locks and names every node pinned at more than one revision, with the members behind
          # each revision.
          #
          # ★★★ THE TWO READINGS ARE OBSERVE-ONLY AND THE REASON IS IN `ci/pin-coherence.nix`'s
          # HEADER, NOT HERE. In one line each: cross-member coherence is FALSE of the ecosystem
          # today (9 of the 10 nodes that can disagree), and hub-root agreement is NOT SATISFIABLE
          # while the member→member ci edge graph holds a cycle — `gen-merge/ci` pins `gen-memo` and
          # `gen-memo/ci` pins `gen-merge`, so each would have to name a commit of the other that
          # names it back. These two readings are cleared by neither a ruling nor a fix available
          # here (den-hoag-6fmmb). The predicate, the domain, the
          # traversal and this message are IDENTICAL under both arms, and only the exit status of a
          # reading differs.
          #   OBSERVE-ONLY, shipped:  an incoherent pin PRINTS and the build passes.
          #   GATING, one edit:       gating = failed != [ ];
          # ★ An ARMING failure exits 1 under BOTH arms. A guard that can no longer fire is not a
          # passing guard in either disposition.
          mkPinCoherenceCheck =
            name: s:
            let
              readings = [
                "pins-cross-member-coherent"
                "pins-match-hub-root"
              ];
              allOk = builtins.all (k: s.gate.${k} == true) s.gateKeys;
              failed = builtins.filter (k: s.gate.${k} != true) s.gateKeys;
              armingFailed = builtins.filter (k: !(builtins.elem k readings)) failed;
              gating = armingFailed != [ ];

              report = builtins.toJSON ({ inherit allOk failed; } // s.report);
              nodeLine =
                r:
                "    ${r.node}: ${toString r.sites} sites, ${toString r.distinct} revisions"
                + lib.concatMapStrings (
                  p:
                  "\n        ${p.rev}  x${toString (builtins.length p.members)}  ${lib.concatStringsSep "," p.members}"
                ) r.pins;
              incoherentRows = builtins.filter (r: builtins.elem r.node s.report.incoherent) s.report.rows;
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                echo "POPULATION: ${toString s.report.memberCount} roster members read of ${toString s.report.memberCount} enumerated, ${toString s.report.nodeCount} shared nodes over ${toString s.report.siteCount} pin sites; ${toString (builtins.length s.report.canDisagree)} nodes pinned by more than one member, ${toString (builtins.length s.report.singlePinned)} single-pinned and therefore unable to disagree."
                echo "HUB-ROOT AXIS: ${toString s.report.agreeingCount} of ${toString s.report.siteCount} sites equal the hub root's resolved revision (${toString (builtins.length s.report.noHubReference)} nodes have no hub root edge at all: ${lib.concatStringsSep " " s.report.noHubReference})."
                ${lib.optionalString (incoherentRows != [ ]) ''
                  echo "PIN COHERENCE — a shared node is pinned at MORE THAN ONE revision across the roster, so a flakeless construction reaching it through two members resolves two store paths and import yields two values (spec S2, L7):" >&2
                  ${lib.concatMapStringsSep "\n" (r: "echo ${lib.escapeShellArg (nodeLine r)} >&2") incoherentRows}
                  echo "Disposed of by converging the members' ci locks onto ONE revision per node — NEVER by narrowing this cell's domain, and NEVER by removing a member's flake input (den-hoag-mehb8 fences that)." >&2
                ''}
                ${lib.optionalString (s.report.refusals != [ ]) ''
                  echo "PIN COHERENCE — this check cannot reach a member lock it enumerates, which is a broken instrument and not a coherence:" >&2
                  ${lib.concatMapStringsSep "\n" (r: "echo ${lib.escapeShellArg "    ${r}"} >&2") s.report.refusals}
                ''}
                echo "ROOT PLANE: ${toString (builtins.length s.report.rootPlaneReading.pathSites)} path-typed gen-* root edges over ${toString s.report.rootPlaneReading.edgeCount} edges in ${toString s.report.rootPlaneReading.readCount} members' own ROOT locks (owner-ruled 2026-09-18: a path: self-reference is legitimate at ci/ ONLY, never at the root). ${toString (builtins.length s.report.rootPlaneReading.lockAbsent)} members declare no root inputs and so have no root lock at all: ${lib.concatStringsSep " " s.report.rootPlaneReading.lockAbsent}"
                ${lib.optionalString (s.report.rootPlaneReading.violations != [ ]) ''
                  echo "ROOT PLANE VIOLATION — a published library's ROOT lock resolves a gen-* edge by path:, carrying a second identity formula for one node into the plane consumers actually resolve through:" >&2
                  ${lib.concatMapStringsSep "\n" (
                    r: "echo ${lib.escapeShellArg "    ${r}"} >&2"
                  ) s.report.rootPlaneReading.violations}
                  echo "Disposed of by relocking that root onto a REVISION. The very same node in that member's ci/ lock is LEGITIMATE and is reported out of domain below — the PLANE is the difference, not the type." >&2
                ''}
                ${lib.optionalString (s.report.exclusions != [ ]) ''
                  echo "OUT OF DOMAIN — ${toString s.report.pathSiteCount} of ${
                    toString (s.report.siteCount + s.report.pathSiteCount)
                  } enumerated sites pin a TREE rather than a publication, so they carry no revision to agree or disagree about and are outside this relation BY TYPE (ci/pin-coherence.nix header). NOT a narrowing of the kind forbidden above: that forbids hiding a real disagreement about a real REVISION, and a path input has none to hide. A revless NON-path node still refuses, by name, one message up."
                  ${lib.concatMapStringsSep "\n" (r: "echo ${lib.escapeShellArg "    ${r}"}") s.report.exclusions}
                ''}
                ${lib.optionalString (armingFailed != [ ]) ''
                  echo "PIN COHERENCE ARMING — a seeded incoherence this cell exists to name went unnamed, or the domain floor stopped discriminating: ${lib.concatStringsSep " " armingFailed}. Read report.arming above: every arm reads its seed AT THE ROW, carrying a revision no live lock can produce" >&2
                ''}
                ${lib.optionalString gating "exit 1"}
                cp "$reportPath" "$out"
              '';
          # Build the inject-payload check (the permanent O-INJ-2 cell): prints the per-key gate
          # and FAILS the build if any key is not `true`. A failing key is either the measured
          # ADR-0023 (b) ground moving (the payload no longer reaches a function — the declared
          # opt-out's disposition re-opens) or a control gone blind; both are red, because a
          # tripwire that can no longer fire is not a passing tripwire.
          mkInjectCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                results = g.gate;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "INJECT-PAYLOAD PREDICATE MOVED — the ADR-0023 (b) measured ground changed, or a control went blind; the declared opt-out's disposition re-opens" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the declared-content check (den-hoag-jwm8 / den-hoag-t3q9): prints the per-key
          # gate and FAILS the build if any key is not `true`. A failing key is the hub realizing a
          # key ADR-0028's Rider excludes — a declared-but-contentless class, or a non-class
          # category whose value is class-shaped — or a control gone blind: the key going
          # unregistered, the tripwire losing its bite, the retired shape test no longer admitting
          # the channel (which would make the wrong-category arm vacuous), or the lexical
          # instrument reading everything as absent.
          mkDeclaredContentCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                results = g.gate;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "DELIVERY-CLASS PROJECTION REGRESSION — the hub realizes a key ADR-0028's Rider excludes, or a control went blind (den-hoag-jwm8 / den-hoag-t3q9)" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # ── perf-regression bench (the PERFORMANCE twin of the parity oracles) ──
          # `nix run ./ci#perf-bench` — drives ci/perf-bench.nix (pure vs pinned-nixpkgs stack)
          # through nix-instantiate + NIX_SHOW_STATS and gates on parity / thunk+alloc ratios /
          # counter linearity — every gate a deterministic evaluator counter. cpu is measured and
          # reported beside them but gated by nothing (ci/README.md). An app, not a check
          # derivation: timing needs an un-sandboxed evaluator run, and the report is regenerated
          # into BENCHMARKS.md. CI runs it as a dedicated workflow step.
          #
          # `gen-class` is the class-share mechanism lib: perf-bench drives its tier-2
          # `applyCoreFixed` against gen-merge's fixed-input kernel (the `classShare` workload —
          # spec §2.5). Like every sibling here it comes through `genInputs` — the root lock's pin,
          # never a local checkout — so the bench measures the pinned revisions
          # and not a developer's working tree.
          perfSrcs = pkgs.writeText "perf-srcs.nix" ''
            {
              "gen-prelude" = "${genInputs.gen-prelude}";
              "gen-types" = "${genInputs.gen-types}";
              "gen-merge" = "${genInputs.gen-merge}";
              "gen-memo" = "${genInputs.gen-memo}";
              "gen-scope" = "${genInputs.gen-scope}";
              "gen-algebra" = "${genInputs.gen-algebra}";
              "gen-identity" = "${genInputs.gen-identity}";
              "gen-schema" = "${genInputs.gen-schema}";
              "gen-aspects" = "${genInputs.gen-aspects}";
              "gen-class" = "${genInputs.gen-class}";
              "gen-schema-orig" = "${inputs.gen-schema-orig}";
              "nixpkgs-lib" = "${inputs.nixpkgs-lib}";
            }
          '';
          # ── the combination the bench TAKES, NAMES and ECHOES (`--at`, and the block in the report) ──
          # `perfSrcs` above stays the BASELINE and nothing else, so an EMPTY overlay passes it
          # through untouched and the CI job is the run this file has always produced. What the app
          # additionally needs in order to NAME a combination is, per key, the revision the baseline
          # resolved to and the upstream flake ref an `--at <k>=rev:…/ref:…` must fetch from. Neither
          # is recoverable from a store path and `genInputs.gen-X` does not carry its own URL, so
          # both are read out of the lock that pinned them — resolved BY PATH from the root, never by
          # node label, because a lock carries duplicate-named nodes (`gen-merge_4`). The `axis`
          # field is what lets the app refuse `--at` on the two REFERENCE keys by name: a ratio's
          # denominator is its control, and if both arms float a moved ratio is unattributable.
          ciLock = builtins.fromJSON (builtins.readFile ./flake.lock);
          perfMemberKeys = [
            "gen-prelude"
            "gen-types"
            "gen-merge"
            "gen-memo"
            "gen-scope"
            "gen-algebra"
            "gen-identity"
            "gen-schema"
            "gen-aspects"
            "gen-class"
          ];
          perfRefKeys = [
            "gen-schema-orig"
            "nixpkgs-lib"
          ];
          # A MEMBER is read from the ROOT lock, the pin set `gen` resolves through; a REFERENCE key
          # is this flake's own declaration and is read from `ci/flake.lock`.
          rootLock = builtins.fromJSON (builtins.readFile ../flake.lock);
          nodeAtIn =
            lock: segs:
            builtins.foldl' (
              node: seg:
              let
                v = lock.nodes.${node}.inputs.${seg};
              in
              # a `follows` edge is a segment path walked from the root, not a node key
              if builtins.isList v then nodeAtIn lock v else v
            ) lock.root segs;
          perfNodeOf =
            k:
            if builtins.elem k perfRefKeys then
              ciLock.nodes.${nodeAtIn ciLock [ k ]}
            else
              rootLock.nodes.${nodeAtIn rootLock [ k ]};
          perfFlakeRefOf =
            k:
            let
              o = (perfNodeOf k).original;
            in
            if o.type or "" == "github" then
              "github:${o.owner}/${o.repo}"
            else
              o.url
                or (throw "ci/flake.nix: perf-bench cannot address '${k}' — its lock `original` names neither a github owner/repo nor a url");
          perfCombination = pkgs.writeText "perf-combination.json" (
            builtins.toJSON (
              builtins.listToAttrs (
                map (k: {
                  name = k;
                  value = {
                    store = if builtins.elem k perfRefKeys then "${inputs.${k}}" else "${genInputs.${k}}";
                    rev = (perfNodeOf k).locked.rev or "";
                    flakeref = perfFlakeRefOf k;
                    axis = if builtins.elem k perfRefKeys then "reference" else "member";
                  };
                }) (perfMemberKeys ++ perfRefKeys)
              )
            )
          );
          perfBench = pkgs.writeShellApplication {
            name = "gen-perf-bench";
            runtimeInputs = [
              pkgs.nix
              pkgs.jq
              pkgs.gawk
            ];
            text = ''
              export PERF_WORKLOADS=${./perf-bench.nix}
              export PERF_SRCS=${perfSrcs}
              export PERF_COMBINATION=${perfCombination}
            ''
            + builtins.readFile ./perf-bench.sh;
          };

          # ── flake-compare bench — the 3-way real-flake comparison ──
          # `nix run ./ci#flake-compare` — evaluates ci/flake-compare/{flake-parts,adios,gen-lib}/
          # (the SAME outputs three ways) under adios-flake's BENCHMARKS.md methodology (5 nix eval
          # runs, NIX_SHOW_STATS counters, eval-cache off), prints a 3-way counter table + drvPath
          # equivalence. Report-only: pins the neighbour frameworks by rev but gates NOTHING (their
          # code moves independently of the hub). The variant flakes carry their own committed locks;
          # `${./flake-compare}` copies the tree (incl locks) to the store for a hermetic run.
          flakeCompare = pkgs.writeShellApplication {
            name = "gen-lib-compare";
            runtimeInputs = [
              pkgs.nix
              pkgs.jq
              pkgs.gawk
              pkgs.coreutils
            ];
            text = ''
              export FLAKE_COMPARE_DIR=${./flake-compare}
            ''
            + builtins.readFile ./flake-compare.sh;
          };

          # ── fleet-consistency — the TRUST-SURFACE arithmetic roster for the cited A1 fleet numbers ──
          # `nix run ./ci#fleet-consistency` — the [consistency] partition (nine pure-jq gates + a
          # `--selftest` teeth check) over the three committed baselines (ci/bench/baselines/, copied
          # verbatim from the hola lab @4bab613). It re-asserts pin agreement, the arithmetic
          # re-derivations, the byte-digest ties, and the two floors that BENCHMARKS.md / VALIDATION.md
          # cite — so the cited numbers cannot silently drift from their own arithmetic. It DOES gate
          # (unlike flake-compare): pure jq, seconds, NO fleet eval / NIX_SHOW_STATS / re-measurement —
          # re-measurement of the fleet is the hola lab's job. Owner principle: libraries stay unburdened
          # by fleet metrics; this hub is the trust surface, so the drift tooth lives here. SC2329: the
          # consistency-gate roster invokes its gate fns indirectly by name.
          fleetConsistency = pkgs.writeShellApplication {
            name = "gen-fleet-consistency";
            excludeShellChecks = [ "SC2329" ];
            runtimeInputs = [
              pkgs.jq
              pkgs.coreutils
            ];
            text = ''
              export FLEET_BASELINES=${./bench/baselines}
            ''
            + builtins.readFile ./fleet-consistency.sh;
          };

          soleEvaluatorReport = mkSoleEvaluatorReport "sole-evaluator" soleEvaluator;

          # ── THE TWO-ACT LOCK BUMP, REACHED À LA CARTE LIKE EVERY OTHER HARNESS GATE HERE ──
          # The hub is not an mkCi consumer — it publishes flake `checks` and perf `app`s rather
          # than a nix-unit `tests` output, so it cannot take the flake module every member takes,
          # and `relock` arrived with that module. Until gen-harness published it as a builder the
          # one command that mutates locks across the whole roster was the single harness surface
          # this repository could not reach, and bumping the hub's own locks stayed the hand-run
          # two-act every member had been relieved of.
          #
          # THE SCANNER, NOT A SECOND CONSTRUCTION OF IT: `relock` execs the self-input predicate
          # over the lock it has just written, and that must be the predicate the check runs.
          # `lib.checks.ciSelfInput` carries it as `passthru.scanner`, so both ends run one
          # implementation. `sourceInfo.outPath` and NOT `outPath`, for the reason given above the
          # sheet check: this subflake is `?dir=ci`.
          #
          # ★ AND THE CHECK IS WIRED TOO, from the SAME derivation. The hub's ci reads the root flake
          # at `self` (den-hoag-lbtnv D1), so the root `flake.lock`'s nodes are in this ci's closure
          # while `ci/flake.lock` holds no copy of them; the harness's scanner reads both locks, and
          # `checks.ci-self-input` runs it over the committed pair on every `nix flake check`.
          ciSelfInput = inputs.gen-harness.lib.checks.ciSelfInput {
            inherit pkgs;
            name = "gen";
            root = self.sourceInfo.outPath;
          };
          relockCmd = inputs.gen-harness.lib.relock {
            inherit pkgs;
            name = "gen";
            inherit (ciSelfInput) scanner;
          };
        in
        {
          # Pre-commit gate for the hub itself. Unlike the lib repos (which consume
          # `gen-harness.lib.mkCi` → its `flakeModule.nix` and get a `ci` nix-unit hook),
          # the hub is the parity/perf harness: it exposes flake `checks` + a perf `app`,
          # NOT a nix-unit `tests` output. So it must NOT carry the shared `ci` hook
          # (`nix-unit --flake ./ci#tests` would fail "does not provide attribute
          # 'tests'"). Format-only here.
          #
          # That is why this flake consumes gen-harness's CHECK BUILDERS rather than its
          # flake module: the hub cannot take a module built around a `tests` output, but
          # the gates themselves are pure functions of `pkgs` and apply here unchanged.
          pre-commit = {
            check.enable = false;
            settings.hooks.treefmt = {
              enable = true;
              package = self'.formatter;
            };
          };

          checks = {
            rehost-den-parity = mkParityCheck "rehost-den-parity" denParity denParityKeys;
            mkgenlibs-eval = mkGenLibsCheck "mkgenlibs-eval" mkGenLibsEval;
            agents-md-hub-inputs = mkHubInputSheetCheck "agents-md-hub-inputs" hubInputSheet;
            inject-payload = mkInjectCheck "inject-payload" injectPayload;
            declared-content = mkDeclaredContentCheck "declared-content" declaredContent;
            direction-of-dependence = mkDirectionCheck "direction-of-dependence" directionOfDependence;
            architecture-library-graph = mkArchitectureGraphCheck "architecture-library-graph" architectureLibraryGraph;
            readme-figures = mkReadmeFiguresCheck "readme-figures" readmeFigures;
            # `sole-evaluator` is NOT here, and its absence is the point: it is reported by
            # `apps.sole-evaluator-report` below. See `mkSoleEvaluatorReport` for the rule.
            pin-coherence = mkPinCoherenceCheck "pin-coherence" pinCoherence;
            hub-entry = mkHubEntryCheck "hub-entry" hubEntry;
            ci-self-input = ciSelfInput;
            ci-declares-no-member =
              let
                failed = builtins.filter (k: ciDeclaresNoMember.gate.${k} != true) ciDeclaresNoMember.gateKeys;
              in
              pkgs.runCommand "ci-declares-no-member"
                {
                  report = builtins.toJSON ({ inherit failed; } // ciDeclaresNoMember.report);
                  passAsFile = [ "report" ];
                }
                ''
                  echo "── ci-declares-no-member ──"
                  cat "$reportPath"
                  echo
                  ${lib.optionalString (failed != [ ]) ''
                    echo ${lib.escapeShellArg "CI DECLARES A MEMBER — ci/flake.nix declares an input named `gen` or `gen-<roster key>`, or the cell's own arming stopped firing: ${lib.concatStringsSep " " failed}. Members are reached through `gen`, the root flake read at `self`, at the root flake.lock's pins; a declaration here re-forms a second pin set (den-hoag-erls, den-hoag-lbtnv D1). Remove the input; never widen the cell."} >&2
                    exit 1
                  ''}
                  cp "$reportPath" "$out"
                '';
            hub-entry-agreement = mkHubEntryAgreementCheck "hub-entry-agreement" hubEntryAgreement;
            hub-substrate = mkHubSubstrateCheck "hub-substrate" hubSubstrate;
            compose-parity =
              let
                failed = builtins.filter (k: composeParity.gate.${k} != true) composeParity.gateKeys;
              in
              pkgs.runCommand "compose-parity"
                {
                  report = builtins.toJSON ({ inherit failed; } // composeParity.report);
                  passAsFile = [ "report" ];
                }
                ''
                  echo "── compose-parity ──"
                  cat "$reportPath"
                  echo
                  ${lib.optionalString (failed != [ ]) ''
                    echo ${lib.escapeShellArg "COMPOSE PARITY BROKEN — warm and cold composes disagree, or a control went blind: ${lib.concatStringsSep " " failed}"} >&2
                    exit 1
                  ''}
                  cp "$reportPath" "$out"
                '';
            # The hub is gated by the same tree-root oracle gen-harness ships to its consumers —
            # the repository that ships a gate is gated by it, and now by the one instance of it
            # rather than by a second copy that has to be kept in agreement.
            treefmt-tree-root = inputs.gen-harness.lib.checks.treefmtTreeRoot {
              inherit pkgs;
              name = "gen";
              formatter = self'.formatter;
            };

            # The plugin set is a property of the GENERATED formatter, not of the expression
            # above: the defect this guards was a list that was written and then discarded.
            # `expected` comes from the same value installed in the treefmt block, so the guard
            # cannot fall behind the set it guards.
            mdformat-plugins = inputs.gen-harness.lib.checks.mdformatPlugins {
              inherit pkgs;
              name = "gen";
              formatter = self'.formatter;
              expected = mdformatBase.names;
            };

            # The hub reaches this gate through `lib.checks` rather than the flake module,
            # because it is not an mkCi consumer — and the hub's ci is exactly the case that
            # symbol is published for. Its sheet is gated for the same reason the hub-input block
            # above is: the repository that ships a gate is gated by it.
            #
            # `sourceInfo.outPath` and NOT `outPath`: this subflake is `?dir=ci`, so the latter
            # is `<root>/ci` and both the sheet and the suite corpus would be sought one
            # directory down, where the check would resolve nothing and say so.
            agents-md-citations = inputs.gen-harness.lib.checks.agentsMdCitations {
              inherit pkgs;
              name = "gen";
              root = self.sourceInfo.outPath;
            };

            # The CI-plane coverage oracle, wired for the same reason as the sheet check above: the
            # hub reaches the harness gates through `lib.checks` rather than the flake module, and
            # until this line existed the hub was the one tree the ecosystem-wide invariant could
            # not see. Being a NAMED MEMBER of the checked set with a verdict is the whole value —
            # the verdict itself is `no-plane`, and that is correct, not a gap to close.
            #
            # `testsError = { }` is the hub's error plane, and it is empty BY CONSTRUCTION: the hub
            # exposes flake `checks` and a perf `app`, not nix-unit `tests`/`testsError` outputs
            # (see the pre-commit block above), so there is no sibling output to read. The check
            # classifies that state `no-plane`. Do not answer this with a `ci/tests-error.nix` —
            # declaring a plane the hub does not run is the exact defect the oracle exists to catch.
            #
            # `sourceInfo.outPath` and NOT `outPath`, for the reason given above the sheet check.
            ci-plane-coverage = inputs.gen-harness.lib.checks.ciPlaneCoverage {
              inherit pkgs;
              name = "gen";
              root = self.sourceInfo.outPath;
              testsError = { };
              # The harness THIS ci is locked to, so the caller's `evaluators.yml@<sha>` is held to
              # it — the value gen-harness's flake module hands every mkCi consumer.
              harnessRev = inputs.gen-harness.sourceInfo.rev or null;
            };

            # readme-audience — a public README carries no internal decision-record reference.
            # A README addresses a reader who does not have the specs, so a ruling is restated as
            # a fact about the design, or replaced by the literature citation underneath it, or
            # the id drops and the sentence carries the content; an `ADR-NNNN` or a tracker id
            # leaves that reader with a pointer they cannot follow. AGENTS.md is deliberately NOT
            # scanned — it addresses readers WITH repo access, where those pointers are the point.
            #
            # This is a gate rather than a convention because the surface was corrected once and
            # re-accreted over six commits in eight days with nobody noticing.
            #
            # The population is the hub plus every roster member, reached through `genInputs` (the
            # route every check here uses), so a new roster library is scanned the moment it becomes a hub
            # input and there is no registration step. An archived or
            # orphaned repository is out by construction: it is off the roster, so it is not a hub
            # input, and a frozen record is not a maintenance target.
            #
            # `sourceInfo.outPath` for the hub's own README, for the reason given just above.
            readme-audience =
              let
                entries = [
                  {
                    name = "gen";
                    src = self.sourceInfo.outPath;
                  }
                ]
                ++ map (n: {
                  name = n;
                  src = "${genInputs.${n}}";
                }) (builtins.filter (n: lib.hasPrefix "gen-" n) (builtins.attrNames genInputs));
              in
              pkgs.runCommand "readme-audience"
                {
                  # Every row TRAILS its newline. `concatMapStringsSep` would leave the last row
                  # without one, and `read` drops an unterminated final line — so the last member
                  # of the population would go unscanned and the run would read clean for it.
                  manifest = lib.concatMapStrings (e: "${e.name} ${e.src}/README.md\n") entries;
                  expected = toString (builtins.length entries);
                  passAsFile = [ "manifest" ];
                }
                ''
                  echo "── readme-audience ──"
                  hits=0
                  scanned=0
                  while read -r name file; do
                    # A missing file makes every predicate below return 0 — live and dead alike —
                    # so absence is a failure here and never a clean row.
                    if [ ! -f "$file" ]; then
                      echo "$name: no README.md at $file" >&2
                      exit 1
                    fi
                    scanned=$((scanned + 1))
                    # ARMING. A real gen README says "gen"; if this stops firing the scan has gone
                    # blind and every zero below is uninterpretable rather than clean.
                    if ! grep -q 'gen' "$file"; then
                      echo "$name: README.md read produced nothing — the scan's own arming stopped firing" >&2
                      exit 1
                    fi
                    # NOT `out`: that name is the derivation's own output path, and shadowing it
                    # leaves the success path redirecting to an empty filename — a failure only
                    # the green arm can reach, which is why this guard was driven green.
                    if found=$(grep -nE 'ADR-[0-9]|den-hoag-' "$file"); then
                      hits=$((hits + 1))
                      echo "$name/README.md" >&2
                      echo "$found" >&2
                    fi
                  done < "$manifestPath"
                  echo "scanned $scanned README.md of $expected, $hits carrying internal references"
                  # TOTALITY. Without this a row lost between the manifest and the loop reads as a
                  # clean member rather than an unscanned one, which is the failure this guard
                  # exists to prevent, one level up.
                  if [ "$scanned" -ne "$expected" ]; then
                    echo "README AUDIENCE SCAN INCOMPLETE — $scanned of $expected READMEs reached the predicate. A zero over a population that was not read is not a clean result" >&2
                    exit 1
                  fi
                  if [ "$hits" -ne 0 ]; then
                    echo "README AUDIENCE REGRESSION — a public README cites an ADR or a tracker id, named with its line above. A reader without the specs cannot resolve either: restate the ruling as a fact about the design, cite the literature underneath it, or drop the id and let the sentence carry the content. AGENTS.md is the surface that keeps its pointers" >&2
                    exit 1
                  fi
                  echo "$scanned" > "$out"
                '';

            # publication-coverage — every publication of the value-injection invariant carries its
            # ADR-0023 interim condition IN THE SAME STATEMENT (the rendered block element, one
            # mermaid node label, or one contiguous comment block). The predicate is
            # `publication-coverage.py`, which scores an in-file arming pair before it reads a file
            # and reds on any claim it cannot place in a unit; its spec is den-ag-design
            # `specs/2026-09-13-gen-invariant-publication-coverage-spec.md`.
            #
            # This is a gate rather than a convention because the condition was dropped twice by
            # rewrites that ran this CI, and the count-vs-fixture probe that preceded it could
            # neither see a new unconditioned statement arrive nor accept a correct repair.
            #
            # The population is EVERY tracked file of the hub, enumerated here by command over the
            # fetched tree — a roster would exclude exactly the file nobody thought published the
            # invariant (the flake-compare header was that file). `sourceInfo.outPath`, not
            # `outPath`, for the reason given above `agents-md-citations`. `expected` is the
            # manifest's own length, and the scan reds when it reaches fewer files than that.
            publication-coverage =
              let
                src = self.sourceInfo.outPath;
                files = map (f: lib.removePrefix "${src}/" (toString f)) (lib.filesystem.listFilesRecursive src);
              in
              pkgs.runCommand "publication-coverage"
                {
                  nativeBuildInputs = [
                    pkgs.python3
                    pkgs.cmark-gfm
                  ];
                  # Every row TRAILS its newline, as in `readme-audience` above.
                  manifest = lib.concatMapStrings (f: f + "\n") files;
                  expected = toString (builtins.length files);
                  passAsFile = [ "manifest" ];
                }
                ''
                  echo "── publication-coverage ──"
                  rc=0
                  python3 ${./publication-coverage.py} ${src} "$manifestPath" "$expected" > report.txt || rc=$?
                  cat report.txt
                  [ "$rc" -eq 0 ] || exit "$rc"
                  cp report.txt "$out"
                '';
          };

          apps.perf-bench = {
            type = "app";
            program = "${perfBench}/bin/gen-perf-bench";
          };

          apps.flake-compare = {
            type = "app";
            program = "${flakeCompare}/bin/gen-lib-compare";
          };

          apps.fleet-consistency = {
            type = "app";
            program = "${fleetConsistency}/bin/gen-fleet-consistency";
          };

          # `nix run ./ci#sole-evaluator-report` — the ADR-0006 / T2(a) scan, REPORTED and gated by
          # nothing. Same criterion, same exception sets, same arming, same tally as when it was a
          # `checks` derivation; only the disposition of a refusal moved. See `mkSoleEvaluatorReport`.
          apps.sole-evaluator-report = {
            type = "app";
            program = "${soleEvaluatorReport}/bin/gen-sole-evaluator-report";
          };

          treefmt = {
            # TREE ROOT — see `gen-harness`'s `flakeModule.nix` for the mechanism in full. A
            # `.git/config` marker walk is worktree-blind: a linked worktree's `.git` is a
            # gitdir-pointer file, so the walk escapes the worktree and formats the main checkout.
            # `null` rather than omission, because flake-parts' `mkDefault "flake.nix"` would pin
            # the tree root to `ci/`; `tree-root-cmd` then STATES the root instead of inheriting
            # treefmt's default.
            # Mirrors the module mkCi hands to consumers — root detection, the program set, and
            # the tree-root check alike: the repo that ships the gate is gated by it, so this list
            # may not be trimmed below the one consumers receive. Since the plugin set and both
            # check builders now come from `gen-harness` itself, that agreement holds by
            # construction rather than by two copies being maintained in step.
            projectRootFile = null;
            flakeCheck = false;
            enableDefaultExcludes = true;
            settings.on-unmatched = "info";
            settings.tree-root-cmd = "git rev-parse --show-toplevel";
            programs = {
              actionlint.enable = true;
              nixfmt.enable = true;
              mdformat = {
                enable = true;
                # ★ THROUGH `plugins`, WITH NO `package` LINE TO GUARD — `package` and `plugins`
                # do not union. treefmt-nix builds `cfg.package.withPlugins cfg.plugins`, and
                # mdformat's `withPlugins` wraps a hardcoded plain base rather than the package
                # it is called on, so a list written into `package` is discarded and the shipped
                # formatter is plain mdformat, store-path-identical to it.
                plugins = mdformatBasePlugins;
                settings.number = true;
              };
            };
          };

          devshells.default = {
            devshell.startup.git-hooks.text = config.pre-commit.installationScript;

            env = [
              {
                name = "FLAKE_ROOT";
                eval = "$PRJ_ROOT";
              }
            ];

            commands = [
              {
                name = "fmt";
                help = "Format all files";
                command = ''
                  cd "$FLAKE_ROOT/ci" && nix fmt
                '';
              }
              {
                name = "relock";
                help = "Bump this repository's locks, root then ci [relock [<input>]]";
                # The same binary every member's devshell carries, built here from the published
                # builder rather than inherited from a module this repository cannot take. It
                # resolves `$FLAKE_ROOT` itself and refuses to leave a self-input violation behind.
                command = ''
                  "${relockCmd}/bin/gen-relock" "$@"
                '';
              }
              {
                name = "repl";
                help = "Interactive REPL with all gen libraries loaded";
                command = ''
                  nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"
                '';
              }
              {
                name = "perf-bench";
                help = "Run the module-system perf-regression bench (pure vs nixpkgs stack)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#perf-bench"
                '';
              }
              {
                name = "flake-compare";
                help = "Run the 3-way real-flake comparison bench (gen-lib vs flake-parts vs adios-flake)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#flake-compare"
                '';
              }
              {
                name = "fleet-consistency";
                help = "Re-assert the [consistency] roster over the cited A1 fleet baselines (pure jq, seconds)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#fleet-consistency"
                '';
              }
            ];
          };
        };
    };
}
