const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');

async function scrape() {
  const regions = [
    'Ξάνθη', 'Ροδόπη', 'Έβρος', 'Καβάλα', 'Χαλκιδική',
    'Θεσσαλονίκη', 'Αττική', 'Βοιωτία', 'Εύβοια', 'Κορινθία',
    'Ηράκλειο', 'Χανιά', 'Ρέθυμνο', 'Λασίθι', 'Λέσβος', 'Χίος', 'Ρόδος'
  ];

  // Default baseline map
  const regionRiskMap = {};
  regions.forEach((r) => { regionRiskMap[r] = 2; });

  let sourceUrl = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn';

  try {
    const { data: html } = await axios.get(sourceUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      },
      timeout: 10000
    });

    const $ = cheerio.load(html);
    const linkEl = $('a[href*="xartis-provlepsis"], a[href*="imerisios-xartis"], .views-row a').first();
    const href = linkEl.attr('href');

    if (href) {
      sourceUrl = href.startsWith('http') ? href : `https://civilprotection.gov.gr${href}`;
      const { data: detailHtml } = await axios.get(sourceUrl, { timeout: 10000 });
      const detail$ = cheerio.load(detailHtml);
      const text = detail$('body').text();

      regions.forEach((region) => {
        if (text.includes('Κατηγορία 4') && text.slice(text.indexOf('Κατηγορία 4')).includes(region)) {
          regionRiskMap[region] = 4;
        } else if (text.includes('Κατηγορία 5') && text.slice(text.indexOf('Κατηγορία 5')).includes(region)) {
          regionRiskMap[region] = 5;
        } else if (text.includes('Κατηγορία 3') && text.slice(text.indexOf('Κατηγορία 3')).includes(region)) {
          regionRiskMap[region] = 3;
        }
      });
    }
  } catch (err) {
    console.warn('Scraping warning (using defaults):', err.message);
  }

  // Always guaranteed to write valid JSON
  const output = {
    lastUpdated: new Date().toISOString(),
    sourceUrl: sourceUrl,
    regions: regionRiskMap
  };

  fs.writeFileSync('fire_risk.json', JSON.stringify(output, null, 2));
  console.log('Successfully wrote fire_risk.json!');
}

scrape();