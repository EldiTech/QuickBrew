#!/usr/bin/env node
/**
 * Direct Seeder Script for Drip & Co Menu and Add-ons
 * Target collections:
 *   - /shops/coffee-shop-a/menu (40 drinks)
 *   - /shops/coffee-shop-a/addons (12 add-ons)
 *
 * Usage:
 *   node scripts/seed_drip_co.js [--email <admin_email>] [--password <admin_pwd>] [--token <id_token>]
 */

const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'quick-brew-64673';
const API_KEY = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk';

// Parse command line arguments
const args = process.argv.slice(2);
function getArg(name, fallback) {
  const idx = args.indexOf(name);
  if (idx !== -1 && idx + 1 < args.length) return args[idx + 1];
  return fallback;
}

const customToken = getArg('--token', null);
const adminEmail = getArg('--email', 'qldespino02@tip.edu.ph');
const adminPassword = getArg('--password', 'moymoy2004');

// 1. Drinks data (40 drinks from drip_co_menu.xlsx)
const DRINKS = [
  // Cà Phê Series
  { name: 'Americano', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Cà Phê Español', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Iced Latte', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Caramel Macchiato', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Salted Caramel Latte', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Oreo Latte', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Dark Mocha Latte', category: 'Cà Phê Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },

  // Premium 45/55
  { name: 'Matcha Fusion', category: 'Premium 45/55', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Strawberry Latte', category: 'Premium 45/55', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Salty Cream Latte', category: 'Premium 45/55', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Salty Cream Americano', category: 'Premium 45/55', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Ube Latte', category: 'Premium 45/55', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },

  // Premium 50/60
  { name: 'Cà Phê Sữa Đá', category: 'Premium 50/60', subCategory: null, sizePrices: { medium: 5000, large: 6000 }, priceCents: null, description: null },
  { name: 'Barista\'s Drink', category: 'Premium 50/60', subCategory: null, sizePrices: { medium: 5000, large: 6000 }, priceCents: null, description: null },
  { name: 'Sea Salt Latte', category: 'Premium 50/60', subCategory: null, sizePrices: { medium: 5000, large: 6000 }, priceCents: null, description: null },
  { name: 'Cinnamon Latte', category: 'Premium 50/60', subCategory: null, sizePrices: { medium: 5000, large: 6000 }, priceCents: null, description: null },

  // Premium
  { name: 'Dolce de Leche', category: 'Premium', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'Velvet Cream Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'Mocha Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'White Mocha Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'Peanut Butter Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'Vanilla Sweet Cream', category: 'Premium', subCategory: null, sizePrices: { medium: 6000, large: 7000 }, priceCents: null, description: null },
  { name: 'Vienna Creamy Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 6000, large: 7000 }, priceCents: null, description: null },
  { name: 'Toffee Nut Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 6000, large: 7000 }, priceCents: null, description: null },
  { name: 'Almond Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 6000, large: 7000 }, priceCents: null, description: null },
  { name: 'Nutella Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 7000, large: 8000 }, priceCents: null, description: null },
  { name: 'Biscoff Latte', category: 'Premium', subCategory: null, sizePrices: { medium: 7000, large: 8000 }, priceCents: null, description: null },

  // Milky Series
  { name: 'Strawberry Milk', category: 'Milky Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Blueberry Milk', category: 'Milky Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Oreo Milk', category: 'Milky Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Swissmiss', category: 'Milky Series', subCategory: null, sizePrices: { medium: 3800, large: 4800 }, priceCents: null, description: null },
  { name: 'Strawberry Oreo', category: 'Milky Series', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Ube Milk', category: 'Milky Series', subCategory: null, sizePrices: { medium: 4500, large: 5500 }, priceCents: null, description: null },
  { name: 'Cocoa', category: 'Milky Series', subCategory: null, sizePrices: { medium: 5500, large: 6500 }, priceCents: null, description: null },
  { name: 'Sea Salt Cocoa', category: 'Milky Series', subCategory: null, sizePrices: { medium: 6500, large: 7500 }, priceCents: null, description: null },
  { name: 'Oreo Cocoa', category: 'Milky Series', subCategory: null, sizePrices: { medium: 6500, large: 7500 }, priceCents: null, description: null },
  { name: 'Milky Biscoff', category: 'Milky Series', subCategory: null, sizePrices: { medium: 6500, large: 7500 }, priceCents: null, description: null },
  { name: 'Milky Nutella', category: 'Milky Series', subCategory: null, sizePrices: { medium: 6500, large: 7500 }, priceCents: null, description: null },

  // Featured / Promo
  { name: 'Cà Phê Trứng (Egg Coffee)', category: 'Featured / Promo', subCategory: null, sizePrices: null, priceCents: 8800, description: 'Venti size' },
  { name: 'Tiramisu Matcha', category: 'Featured / Promo', subCategory: null, sizePrices: null, priceCents: 9800, description: 'Venti size' }
];

// 2. Add-ons data (12 add-ons from drip_co_menu.xlsx)
const ADDONS = [
  { name: 'Extra Shot', priceCents: 2000, group: 'Coffee' },
  { name: 'Syrups / Drizzle', priceCents: 1500, group: 'Drizzle' },
  { name: 'Bobba Pearl', priceCents: 1000, group: 'Sinkers' },
  { name: 'Nata', priceCents: 1000, group: 'Sinkers' },
  { name: 'Oreo', priceCents: 1500, group: 'Sinkers' },
  { name: 'Coffee Jelly', priceCents: 1500, group: 'Sinkers' },
  { name: 'Milo', priceCents: 1500, group: 'Sinkers' },
  { name: 'Cream Cheese', priceCents: 1500, group: 'Toppings' },
  { name: 'Salty Cream', priceCents: 1500, group: 'Toppings' },
  { name: 'Whip Cream', priceCents: 1500, group: 'Toppings' },
  { name: 'Sea Salt', priceCents: 1500, group: 'Toppings' },
  { name: 'Oatside', priceCents: 3000, group: 'Milk choice' }
];

async function authenticate() {
  if (customToken) return customToken;
  console.log(`Authenticating with Firebase Auth as ${adminEmail}...`);
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: adminEmail, password: adminPassword, returnSecureToken: true })
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Authentication failed (${res.status}): ${JSON.stringify(data.error)}`);
  }
  console.log(`Authenticated successfully. UID: ${data.localId}`);
  return data.idToken;
}

function drinkToFirestoreFields(item, sort) {
  const fields = {
    name: { stringValue: item.name },
    category: { stringValue: item.category },
    sort: { doubleValue: sort },
    imageBase64: { nullValue: null }
  };

  if (item.subCategory) {
    fields.subCategory = { stringValue: item.subCategory };
  } else {
    fields.subCategory = { nullValue: null };
  }

  if (item.description) {
    fields.description = { stringValue: item.description };
  } else {
    fields.description = { nullValue: null };
  }

  if (item.sizePrices) {
    const sizeMap = {};
    for (const [s, price] of Object.entries(item.sizePrices)) {
      sizeMap[s] = { integerValue: price.toString() };
    }
    fields.sizePrices = { mapValue: { fields: sizeMap } };
    fields.priceCents = { nullValue: null };
  } else {
    fields.sizePrices = { nullValue: null };
    fields.priceCents = { integerValue: item.priceCents.toString() };
  }

  return fields;
}

function addOnToFirestoreFields(addOn, sort) {
  return {
    name: { stringValue: addOn.name },
    priceCents: { integerValue: addOn.priceCents.toString() },
    group: { stringValue: addOn.group },
    sort: { doubleValue: sort }
  };
}

async function writeDocument(collectionPath, fields, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionPath}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ fields })
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Write to ${collectionPath} failed (${res.status}): ${text}`);
  }
  return await res.json();
}

async function seed() {
  console.log('=== Drip & Co Menu Seeder ===');
  console.log(`Target: shops/coffee-shop-a`);
  console.log(`Menu Items: ${DRINKS.length}`);
  console.log(`Add-ons: ${ADDONS.length}\n`);

  let token;
  try {
    token = await authenticate();
  } catch (err) {
    console.error('Auth Error:', err.message);
    process.exit(1);
  }

  // 1. Seed Menu
  console.log(`\nSeeding ${DRINKS.length} menu drinks into shops/coffee-shop-a/menu...`);
  let menuSuccess = 0;
  for (let i = 0; i < DRINKS.length; i++) {
    const drink = DRINKS[i];
    const fields = drinkToFirestoreFields(drink, i);
    try {
      await writeDocument('shops/coffee-shop-a/menu', fields, token);
      menuSuccess++;
      process.stdout.write(`  [${menuSuccess}/${DRINKS.length}] Added: ${drink.name}\n`);
    } catch (err) {
      console.error(`  FAILED: ${drink.name} - ${err.message}`);
      if (err.message.includes('403') || err.message.includes('PERMISSION_DENIED')) {
        console.error('\nStopping: Account does not have admin permissions in firestore.rules.');
        console.error('Note: Use Firebase Console to set role: "superadmin" on users/<uid>, then rerun.\n');
        break;
      }
    }
  }

  // 2. Seed Add-ons
  if (menuSuccess > 0) {
    console.log(`\nSeeding ${ADDONS.length} add-ons into shops/coffee-shop-a/addons...`);
    let addonSuccess = 0;
    for (let i = 0; i < ADDONS.length; i++) {
      const addOn = ADDONS[i];
      const fields = addOnToFirestoreFields(addOn, i);
      try {
        await writeDocument('shops/coffee-shop-a/addons', fields, token);
        addonSuccess++;
        process.stdout.write(`  [${addonSuccess}/${ADDONS.length}] Added: ${addOn.name} (${addOn.group})\n`);
      } catch (err) {
        console.error(`  FAILED: ${addOn.name} - ${err.message}`);
      }
    }
    console.log(`\nSummary: Successfully seeded ${menuSuccess} drinks and ${addonSuccess} add-ons!`);
  }
}

seed();
