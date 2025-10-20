#!/bin/bash

# Firestore Rules Deployment Script
# Usage: ./DEPLOY_FIRESTORE_RULES.sh

echo "🔐 Deploying Firestore Security Rules..."
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not installed"
    echo "Install with: npm install -g firebase-tools"
    exit 1
fi

# Check if logged in
echo "📋 Checking Firebase login status..."
firebase login:list

echo ""
echo "🚀 Deploying rules to Firebase..."
firebase deploy --only firestore:rules

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Test parent app: Create family and get 4-digit code"
echo "2. Test child app: Enter code and approve connection"
echo "3. Verify both apps can access family data"
echo ""
echo "📖 See FIRESTORE_RULES_IMPLEMENTATION_GUIDE.md for testing checklist"
