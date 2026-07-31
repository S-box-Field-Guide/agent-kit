# Contributing

agent-kit is generated. Every file here is produced by an automated pipeline that mirrors a private knowledge base, and entries are verified on a live s&box editor before anything ships. This repo is the last step in that chain, not the first.

That has one awkward consequence: **pull requests can't be merged here.** A direct change to this repo would be overwritten by the next sync, and merges would also break the repo's single-author history. A closed PR is a limitation of the pipeline, not a judgment on your patch.

What works instead:

- Open an issue (or a PR, if a diff is the clearest way to show the problem; just know it gets closed rather than merged). Describe what's wrong or missing: the claim, the engine build you saw it on, and how to reproduce it.
- A maintainer verifies the report against the engine. Verified fixes get written into the upstream knowledge base and flow out through the next sync, usually within a day or two.
- You'll get a reply on your issue or PR either way, covering what was tested and what happened, plus a follow-up when a fix is live.

Corrections are welcome, and verified reports make the pack better for everyone. The fastest path is the Field Guide Discord (linked from [sboxguide.dev](https://sboxguide.dev)), where reports go through the same verification pipeline.
