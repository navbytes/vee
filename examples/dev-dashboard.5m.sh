#!/bin/bash
# <xbar.title>Dev Dashboard</xbar.title>
# <xbar.version>1.0.0</xbar.version>
# <xbar.author>Vee</xbar.author>
# <xbar.desc>A deliberately large, deeply-nested menu: repos, PRs, branches, CI jobs, containers, k8s contexts, scripts, and bookmarks. Demonstrates Vee's searchable filter panel — too many items to scroll, easy to fuzzy-find.</xbar.desc>
# <xbar.dependencies>bash</xbar.dependencies>
#
# Opt this plugin into Vee's searchable filter panel: typing filters every item
# across all submenus at once, with breadcrumbs. Try it from the CLI today:
#   vee search examples/dev-dashboard.5m.sh "retry"
#   vee search examples/dev-dashboard.5m.sh "prod deploy"
# <vee.filter>true</vee.filter>
#
# Optionally bind a global hotkey that opens the search panel from anywhere
# (opt-in; omit the tag for no hotkey):
# <vee.shortcut>cmd+shift+k</vee.shortcut>

echo "🧰 Dev"
echo "---"

# ── Repositories ────────────────────────────────────────────────────────────
echo "Repositories | sfimage=folder"
echo "--orders"
echo "----Open on GitHub | href=https://github.com/acme/orders"
echo "----Pull Requests"
echo "------#412 Fix retry backoff jitter | href=https://github.com/acme/orders/pull/412"
echo "------#409 Add circuit breaker to scheduler | href=https://github.com/acme/orders/pull/409"
echo "------#401 Bump swift-tools to 6.2 | href=https://github.com/acme/orders/pull/401"
echo "------#398 Flaky soak test on wake | href=https://github.com/acme/orders/pull/398"
echo "----Branches"
echo "------main | bash=/bin/echo param0=checkout param1=main terminal=false"
echo "------feature/retry-jitter | bash=/bin/echo param0=checkout param1=retry-jitter terminal=false"
echo "------fix/scheduler-leak | bash=/bin/echo param0=checkout param1=scheduler-leak terminal=false"
echo "--webconsole"
echo "----Open on GitHub | href=https://github.com/acme/webconsole"
echo "----Pull Requests"
echo "------#77 Dark mode tokens | href=https://github.com/acme/webconsole/pull/77"
echo "------#75 Virtualize the events table | href=https://github.com/acme/webconsole/pull/75"
echo "----Branches"
echo "------main | bash=/bin/echo param0=checkout param1=main terminal=false"
echo "------feature/dark-mode | bash=/bin/echo param0=checkout param1=dark-mode terminal=false"
echo "--infra"
echo "----Open on GitHub | href=https://github.com/acme/infra"
echo "----Pull Requests"
echo "------#233 Terraform: prod VPC peering | href=https://github.com/acme/infra/pull/233"
echo "------#231 Rotate RDS credentials | href=https://github.com/acme/infra/pull/231"

# ── CI / Pipelines ──────────────────────────────────────────────────────────
echo "CI / Pipelines | sfimage=hammer"
echo "--orders · build & test | href=https://ci.acme.dev/orders/build"
echo "--orders · nightly soak | href=https://ci.acme.dev/orders/soak"
echo "--webconsole · lint & unit | href=https://ci.acme.dev/webconsole/lint"
echo "--webconsole · e2e (playwright) | href=https://ci.acme.dev/webconsole/e2e"
echo "--infra · terraform plan | href=https://ci.acme.dev/infra/plan"
echo "--infra · terraform apply (prod) | href=https://ci.acme.dev/infra/apply-prod"

# ── Containers ──────────────────────────────────────────────────────────────
echo "Containers | sfimage=shippingbox"
echo "--postgres:16 (healthy) | bash=/bin/echo param0=logs param1=postgres terminal=true"
echo "--redis:7 (healthy) | bash=/bin/echo param0=logs param1=redis terminal=true"
echo "--orders-api (restarting) | color=orange | bash=/bin/echo param0=logs param1=api terminal=true"
echo "--webconsole-dev (healthy) | bash=/bin/echo param0=logs param1=web terminal=true"
echo "--mailhog (healthy) | bash=/bin/echo param0=logs param1=mailhog terminal=true"

# ── Kubernetes ──────────────────────────────────────────────────────────────
echo "Kubernetes | sfimage=helm"
echo "--Contexts"
echo "----prod-us-east-1 | bash=/bin/echo param0=use-context param1=prod-us-east-1 terminal=false"
echo "----prod-eu-west-1 | bash=/bin/echo param0=use-context param1=prod-eu-west-1 terminal=false"
echo "----staging | bash=/bin/echo param0=use-context param1=staging terminal=false"
echo "----minikube | bash=/bin/echo param0=use-context param1=minikube terminal=false"
echo "--Deploy to prod (us-east-1) | bash=/bin/echo param0=rollout param1=prod terminal=true"
echo "--Roll back last deploy | color=red | bash=/bin/echo param0=rollback terminal=true"

# ── Scripts ─────────────────────────────────────────────────────────────────
echo "Scripts | sfimage=terminal"
echo "--npm run dev | bash=/bin/echo param0=npm param1=dev terminal=true"
echo "--npm run build | bash=/bin/echo param0=npm param1=build terminal=true"
echo "--npm run test:watch | bash=/bin/echo param0=npm param1=test terminal=true"
echo "--npm run lint:fix | bash=/bin/echo param0=npm param1=lint terminal=true"
echo "--make migrate | bash=/bin/echo param0=make param1=migrate terminal=true"
echo "--make seed | bash=/bin/echo param0=make param1=seed terminal=true"

# ── Bookmarks ───────────────────────────────────────────────────────────────
echo "Bookmarks | sfimage=bookmark"
echo "--Grafana · service overview | href=https://grafana.acme.dev/d/overview"
echo "--Sentry · unresolved issues | href=https://sentry.acme.dev/acme/issues"
echo "--Statuspage · incidents | href=https://status.acme.dev"
echo "--Notion · runbooks | href=https://notion.so/acme/runbooks"
echo "--Figma · design system | href=https://figma.com/acme/design-system"

echo "---"
echo "Refresh | refresh=true | sfimage=arrow.clockwise"
