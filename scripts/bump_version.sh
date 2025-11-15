#!/bin/bash
set -e

# Usage: ./scripts/bump_version.sh <version>
# Example: ./scripts/bump_version.sh 0.2.0

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.2.0"
  exit 1
fi

NEW_VERSION=$1
TODAY=$(date +%Y-%m-%d)

echo "Bumping version to $NEW_VERSION..."

# Update mix.exs
echo "Updating mix.exs..."
sed -i.bak "s/version: \".*\"/version: \"$NEW_VERSION\"/" mix.exs
rm mix.exs.bak

# Update CHANGELOG.md
echo "Updating CHANGELOG.md..."
# Create new version entry
TEMP_FILE=$(mktemp)
{
  # Keep everything before [Unreleased]
  sed -n '1,/## \[Unreleased\]/p' CHANGELOG.md
  
  # Add new version section
  echo ""
  echo "## [$NEW_VERSION] - $TODAY"
  echo ""
  echo "### Added"
  echo "- "
  echo ""
  echo "### Changed"
  echo "- "
  echo ""
  echo "### Fixed"
  echo "- "
  
  # Keep the rest of the file
  sed -n '/## \[Unreleased\]/,$p' CHANGELOG.md | tail -n +2
} > "$TEMP_FILE"

mv "$TEMP_FILE" CHANGELOG.md

echo "✓ Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "1. Edit CHANGELOG.md to add your changes"
echo "2. Review the changes: git diff"
echo "3. Commit: git add mix.exs CHANGELOG.md && git commit -m 'Bump version to $NEW_VERSION'"
echo "4. Tag: git tag v$NEW_VERSION"
echo "5. Push: git push origin main && git push origin v$NEW_VERSION"
