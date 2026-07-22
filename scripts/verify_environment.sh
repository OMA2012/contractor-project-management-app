#!/usr/bin/env bash
set -u

repo_root="${1:-$(pwd)}"
status=0

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%-14s FOUND   %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '%-14s MISSING\n' "$command_name"
    status=1
  fi
}

echo "Package 09.1 repository and environment verification"
echo "Repository root: $repo_root"
echo

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Git repository: FOUND"
  echo "Branch: $(git -C "$repo_root" branch --show-current)"
  echo "HEAD: $(git -C "$repo_root" rev-parse --short HEAD)"
else
  echo "Git repository: MISSING"
  status=1
fi

echo
for tool in git flutter dart supabase docker node npm deno psql python3; do
  check_command "$tool"
done

echo
for path in \
  supabase/config.toml \
  supabase/migrations \
  supabase/tests \
  .github/workflows; do
  if test -e "$repo_root/$path"; then
    echo "$path: FOUND"
  else
    echo "$path: MISSING"
    status=1
  fi
done

echo
if grep -RInE --exclude='.env.example' --exclude='verify_environment.sh' --exclude-dir='.git' \
  '(SUPABASE_SERVICE_ROLE_KEY=(eyJ|sb_secret_|[A-Za-z0-9_-]{24,})|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|sk_live_)' \
  "$repo_root" >/tmp/package_09_1_secret_scan.txt 2>/dev/null; then
  echo "Potential committed secret material: FOUND"
  cat /tmp/package_09_1_secret_scan.txt
  status=1
else
  echo "Potential committed secret material: none detected by baseline scan"
fi

exit "$status"
