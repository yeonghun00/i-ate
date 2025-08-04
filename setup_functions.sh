#!/bin/bash

echo "🚀 Setting up Firebase Functions for FCM notifications..."

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Installing..."
    npm install -g firebase-tools
else
    echo "✅ Firebase CLI found"
fi

# Install dependencies
echo "📦 Installing Functions dependencies..."
cd functions
npm install
cd ..

# Build the functions
echo "🔨 Building TypeScript functions..."
cd functions
npm run build
cd ..

echo "✅ Setup complete! Now run these commands:"
echo ""
echo "1. Login to Firebase:"
echo "   firebase login"
echo ""
echo "2. Set your project:"
echo "   firebase use thanks-everyday"
echo ""
echo "3. Deploy functions:"
echo "   firebase deploy --only functions"
echo ""
echo "4. Test by clicking 'I ate' in your app!"
echo ""
echo "🎉 After deployment, FCM notifications will work automatically!"