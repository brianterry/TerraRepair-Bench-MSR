# License texts for third-party Terraform modules

Add the full text of each license below before publishing. Each file must be the
unmodified official text. Running this from the repository root fetches them:

    curl -fsSL -o LICENSES/MPL-2.0.txt   https://raw.githubusercontent.com/spdx/license-list-data/main/text/MPL-2.0.txt
    curl -fsSL -o LICENSES/GPL-3.0.txt   https://raw.githubusercontent.com/spdx/license-list-data/main/text/GPL-3.0-only.txt
    curl -fsSL -o LICENSES/AGPL-3.0.txt  https://raw.githubusercontent.com/spdx/license-list-data/main/text/AGPL-3.0-only.txt
    curl -fsSL -o LICENSES/Apache-2.0.txt https://raw.githubusercontent.com/spdx/license-list-data/main/text/Apache-2.0.txt

MIT notices are short and carry each repository's own copyright line, so they are
best kept with the per-repository entries in THIRD_PARTY_LICENSES.md.

Which modules each license covers is listed in THIRD_PARTY_LICENSES.md and in the
license_spdx column of data/terrads_provenance.csv.
