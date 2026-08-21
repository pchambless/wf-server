#!/bin/bash
# Seed account 3 ("Test Bed") with deliberately-labeled minimal fixtures and a
# scoped tester user, then point context_store at them - so
# check-dropdown-health.sh has real fixture data to render against instead of
# borrowing pc7900@gmail.com's account by accident.
#
# WHY (task 284): the dropdown health check currently passes only because
# pc7900@gmail.com's real account happens to already have every context key
# populated from ordinary use - that's a coincidence, not a fixture. Account 3
# already exists for this purpose but had 0 batches and 0 lineage rows, so
# ingredient_batch_id/product_batch_id have never been populated for anyone.
#
# Creates, idempotently (matched by email/name, safe to re-run):
#   - whatsfresh.users: one tester, bcrypt hash of a discarded random string -
#     this account is never meant to authenticate through the UI, only to
#     exist as a context_store.email key.
#   - whatsfresh.accounts_users: tester scoped to account_id=3 ONLY.
#   - whatsfresh.entity_types: "Ingredient Type 1" (Shop), "Product Type 1" (Prod)
#   - whatsfresh.entities: "Ingredient 1", "Ingredient 2" (Shop), "Product 1" (Prod)
#   - whatsfresh.product_recipes: Product 1 <- Ingredient 1, Ingredient 2
#   - whatsfresh.batches: one batch each for the 3 entities above
#   - whatsfresh.lineage: both ingredient batches -> the product batch
#     (event_type Shop->Prod, the convention already in use elsewhere)
#   - whatsfresh.context_store: the 8 keys the 6 dropdown templates' hydrate
#     SQL actually references, populated for the tester email
#
# Usage: setup-test-bed.sh [dev|prod|all]
#   Default: all - Test Bed data must match on both dev and prod (task 284).
#
# Requires: curl, jq

set -e

SCOPE="${1:-all}"
TESTER_EMAIL="testbed@whatsfresh.app"
# bcrypt hash of a discarded random string - see setup-test-bed generation
# note in task 284. Nobody knows the plaintext; this can never authenticate.
TESTER_PASSWORD_HASH='$2b$10$UmX56mqj1OnD8YDoIPaPnuBmPcFhaT2jZdDYXjltGEvlfHQ8S8.dy'

declare -A ENV_URLS=( [dev]="https://n8n.whatsfresh.app" [prod]="https://v2-n8n.whatsfresh.app" )

case "$SCOPE" in
  dev|prod) TARGETS=("$SCOPE") ;;
  all)      TARGETS=(dev prod) ;;
  *) echo "Usage: setup-test-bed.sh [dev|prod|all]" >&2; exit 1 ;;
esac

# :email / :password_hash are substituted server-side by server-query's L01
# code node (regex replace against params, auto-quoted/escaped) - not bash
# interpolation, so no quoting hazards from the surrounding DO block.
read -r -d '' SETUP_SQL <<'SQL' || true
DO $testbed$
DECLARE
  v_tester_id integer;
  v_ing_type_id integer;
  v_prod_type_id integer;
  v_ing1_id integer;
  v_ing2_id integer;
  v_prod1_id integer;
  v_recipe1_id integer;
  v_recipe2_id integer;
  v_ing1_batch_id integer;
  v_ing2_batch_id integer;
  v_prod1_batch_id integer;
BEGIN
  SELECT id INTO v_tester_id FROM whatsfresh.users WHERE email = :email;
  IF v_tester_id IS NULL THEN
    INSERT INTO whatsfresh.users (email, password, first_name, last_name, role, default_account_id, must_change_password, created_by)
    VALUES (:email, :password_hash, 'Test', 'Bed', 1, 3, false, 'claude')
    RETURNING id INTO v_tester_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.accounts_users WHERE user_id = v_tester_id AND account_id = 3) THEN
    INSERT INTO whatsfresh.accounts_users (account_id, user_id, is_owner, created_by)
    VALUES (3, v_tester_id, 0, 'claude');
  END IF;

  SELECT id INTO v_ing_type_id FROM whatsfresh.entity_types WHERE account_id = 3 AND name = 'Ingredient Type 1' AND entity_kind = 'Shop' AND deleted_at IS NULL;
  IF v_ing_type_id IS NULL THEN
    INSERT INTO whatsfresh.entity_types (account_id, name, entity_kind, description, created_by)
    VALUES (3, 'Ingredient Type 1', 'Shop', 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_ing_type_id;
  END IF;

  SELECT id INTO v_prod_type_id FROM whatsfresh.entity_types WHERE account_id = 3 AND name = 'Product Type 1' AND entity_kind = 'Prod' AND deleted_at IS NULL;
  IF v_prod_type_id IS NULL THEN
    INSERT INTO whatsfresh.entity_types (account_id, name, entity_kind, description, created_by)
    VALUES (3, 'Product Type 1', 'Prod', 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_prod_type_id;
  END IF;

  SELECT id INTO v_ing1_id FROM whatsfresh.entities WHERE account_id = 3 AND name = 'Ingredient 1' AND entity_kind = 'Shop' AND deleted_at IS NULL;
  IF v_ing1_id IS NULL THEN
    INSERT INTO whatsfresh.entities (account_id, name, entity_kind, entity_type_id, description, created_by)
    VALUES (3, 'Ingredient 1', 'Shop', v_ing_type_id, 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_ing1_id;
  END IF;

  SELECT id INTO v_ing2_id FROM whatsfresh.entities WHERE account_id = 3 AND name = 'Ingredient 2' AND entity_kind = 'Shop' AND deleted_at IS NULL;
  IF v_ing2_id IS NULL THEN
    INSERT INTO whatsfresh.entities (account_id, name, entity_kind, entity_type_id, description, created_by)
    VALUES (3, 'Ingredient 2', 'Shop', v_ing_type_id, 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_ing2_id;
  END IF;

  SELECT id INTO v_prod1_id FROM whatsfresh.entities WHERE account_id = 3 AND name = 'Product 1' AND entity_kind = 'Prod' AND deleted_at IS NULL;
  IF v_prod1_id IS NULL THEN
    INSERT INTO whatsfresh.entities (account_id, name, entity_kind, entity_type_id, description, created_by)
    VALUES (3, 'Product 1', 'Prod', v_prod_type_id, 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_prod1_id;
  END IF;

  SELECT id INTO v_recipe1_id FROM whatsfresh.product_recipes WHERE product_id = v_prod1_id AND ingredient_id = v_ing1_id AND deleted_at IS NULL;
  IF v_recipe1_id IS NULL THEN
    INSERT INTO whatsfresh.product_recipes (product_id, ingredient_id, ingredient_order, quantity, comments, created_by)
    VALUES (v_prod1_id, v_ing1_id, 1, 1, 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_recipe1_id;
  END IF;

  SELECT id INTO v_recipe2_id FROM whatsfresh.product_recipes WHERE product_id = v_prod1_id AND ingredient_id = v_ing2_id AND deleted_at IS NULL;
  IF v_recipe2_id IS NULL THEN
    INSERT INTO whatsfresh.product_recipes (product_id, ingredient_id, ingredient_order, quantity, comments, created_by)
    VALUES (v_prod1_id, v_ing2_id, 2, 1, 'Test Bed fixture - task 284', 'claude')
    RETURNING id INTO v_recipe2_id;
  END IF;

  SELECT id INTO v_ing1_batch_id FROM whatsfresh.batches WHERE account_id = 3 AND entity_kind = 'Shop' AND entity_id = v_ing1_id AND batch_number = 'TB-ING1-01' AND deleted_at IS NULL;
  IF v_ing1_batch_id IS NULL THEN
    INSERT INTO whatsfresh.batches (account_id, entity_kind, entity_id, batch_number, quantity, event_date, comments, created_by, created_at)
    VALUES (3, 'Shop', v_ing1_id, 'TB-ING1-01', 10, CURRENT_DATE, 'Test Bed fixture - task 284', 'claude', now())
    RETURNING id INTO v_ing1_batch_id;
  END IF;

  SELECT id INTO v_ing2_batch_id FROM whatsfresh.batches WHERE account_id = 3 AND entity_kind = 'Shop' AND entity_id = v_ing2_id AND batch_number = 'TB-ING2-01' AND deleted_at IS NULL;
  IF v_ing2_batch_id IS NULL THEN
    INSERT INTO whatsfresh.batches (account_id, entity_kind, entity_id, batch_number, quantity, event_date, comments, created_by, created_at)
    VALUES (3, 'Shop', v_ing2_id, 'TB-ING2-01', 10, CURRENT_DATE, 'Test Bed fixture - task 284', 'claude', now())
    RETURNING id INTO v_ing2_batch_id;
  END IF;

  SELECT id INTO v_prod1_batch_id FROM whatsfresh.batches WHERE account_id = 3 AND entity_kind = 'Prod' AND entity_id = v_prod1_id AND batch_number = 'TB-PROD1-01' AND deleted_at IS NULL;
  IF v_prod1_batch_id IS NULL THEN
    INSERT INTO whatsfresh.batches (account_id, entity_kind, entity_id, batch_number, quantity, event_date, comments, created_by, created_at)
    VALUES (3, 'Prod', v_prod1_id, 'TB-PROD1-01', 5, CURRENT_DATE, 'Test Bed fixture - task 284', 'claude', now())
    RETURNING id INTO v_prod1_batch_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.lineage WHERE account_id = 3 AND source_batch_id = v_ing1_batch_id AND target_batch_id = v_prod1_batch_id) THEN
    INSERT INTO whatsfresh.lineage (account_id, event_type, source_batch_id, target_batch_id, comments, created_by, created_at)
    VALUES (3, 'Shop->Prod', v_ing1_batch_id, v_prod1_batch_id, 'Test Bed fixture - task 284', 'claude', now());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.lineage WHERE account_id = 3 AND source_batch_id = v_ing2_batch_id AND target_batch_id = v_prod1_batch_id) THEN
    INSERT INTO whatsfresh.lineage (account_id, event_type, source_batch_id, target_batch_id, comments, created_by, created_at)
    VALUES (3, 'Shop->Prod', v_ing2_batch_id, v_prod1_batch_id, 'Test Bed fixture - task 284', 'claude', now());
  END IF;

  INSERT INTO whatsfresh.context_store (param_name, param_val, email, created_by)
  VALUES
    ('account_id', '3', :email, 'claude'),
    ('ingredient_id', v_ing1_id::text, :email, 'claude'),
    ('ingredient_type_id', v_ing_type_id::text, :email, 'claude'),
    ('ingredient_batch_id', v_ing1_batch_id::text, :email, 'claude'),
    ('product_id', v_prod1_id::text, :email, 'claude'),
    ('product_type_id', v_prod_type_id::text, :email, 'claude'),
    ('product_batch_id', v_prod1_batch_id::text, :email, 'claude'),
    ('recipe_id', v_recipe1_id::text, :email, 'claude')
  ON CONFLICT (email, param_name) DO UPDATE SET param_val = EXCLUDED.param_val, updated_by = 'claude', updated_at = now();
END
$testbed$ LANGUAGE plpgsql;
SQL

VERIFY_SQL="SELECT u.id user_id, u.email, au.account_id, cs.param_name, cs.param_val
FROM whatsfresh.users u
JOIN whatsfresh.accounts_users au ON au.user_id = u.id
LEFT JOIN whatsfresh.context_store cs ON cs.email = u.email AND cs.deleted_at IS NULL
WHERE u.email = :email
ORDER BY cs.param_name"

for ENV in "${TARGETS[@]}"; do
  BASE_URL="${ENV_URLS[$ENV]}"
  echo "[test-bed] Seeding $ENV..."

  SETUP_PAYLOAD=$(jq -n --arg q "$SETUP_SQL" --arg email "$TESTER_EMAIL" --arg hash "$TESTER_PASSWORD_HASH" \
    '{query: $q, params: {email: $email, password_hash: $hash}, source: "setup-test-bed"}')
  SETUP_RESPONSE=$(curl -s -X POST "$BASE_URL/webhook/server-query" -H "Content-Type: application/json" -d "$SETUP_PAYLOAD")

  if echo "$SETUP_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    echo "[test-bed] FAIL  $ENV: $SETUP_RESPONSE"
    exit 1
  fi

  VERIFY_PAYLOAD=$(jq -n --arg q "$VERIFY_SQL" --arg email "$TESTER_EMAIL" \
    '{query: $q, params: {email: $email}, source: "setup-test-bed"}')
  VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/webhook/server-query" -H "Content-Type: application/json" -d "$VERIFY_PAYLOAD")

  ROW_COUNT=$(echo "$VERIFY_RESPONSE" | jq 'length' 2>/dev/null || echo 0)
  if [ "$ROW_COUNT" -lt 8 ]; then
    echo "[test-bed] FAIL  $ENV: expected 8 context_store rows for $TESTER_EMAIL, got $ROW_COUNT - $VERIFY_RESPONSE"
    exit 1
  fi

  echo "[test-bed] OK    $ENV: tester scoped to account 3, $ROW_COUNT/8 context_store keys populated"
  echo "$VERIFY_RESPONSE" | jq -r '.[] | "  \(.param_name) = \(.param_val)"'
done

echo ""
echo "[test-bed] Done. Point check-dropdown-health.sh at $TESTER_EMAIL to use these fixtures:"
echo "  bash scripts/check-dropdown-health.sh all $TESTER_EMAIL"
