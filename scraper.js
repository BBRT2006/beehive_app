const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');

async function scrape() {
  try {
    const archiveUrl = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn';
    const { data: html } = await axios.get(archiveUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
    });

    const $ = cheerio.load(html);
    const latestMapLink = $('.views-row a').first().attr('href');
    if (!latestMapLink) return;

    const fullUrl = latestMapLink.startsWith('http')
      ? latestMapLink
      : `https://civilprotection.gov.gr${latestMapLink}`;

    const { data: detailHtml } = await axios.get(fullUrl);
    const detail$ = cheerio.load(detailHtml);
    const textContent = detail$('body').text();

    const regions = [
      'Ξάνθη', 'Ροδόπη', 'Έβρος', 'Καβάλα', 'Χαλκιδική',
      'Θεσσαλονίκη', 'Αττική', 'Βοιωτία', 'Εύβοια', 'Κορινθία',
      'Ηράκλειο', 'Χανιά', 'Ρέθυμνο', 'Λασίθι', 'Λέσβος', 'Χίος', 'Ρόδος'
    ];

    const regionRiskMap = {};
    regions.forEach((region) => {
      let category = 2; // Default baseline

      if (
        textContent.includes('Κατηγορία 4') &&
        textContent.slice(textContent.indexOf('Κατηγορία 4')).includes(region)
      ) {
        category = 4;
      } else if (
        textContent.includes('Κατηγορία 5') &&
        textContent.slice(textContent.indexOf('Κατηγορία 5')).includes(region)
      ) {
        category = 5;
      } else if (
        textContent.includes('Κατηγορία 3') &&
        textContent.slice(textContent.indexOf('Κατηγορία 3')).includes(region)
      ) {
        category = 3;
      }

      regionRiskMap[region] = category;
    });

    const output = {
      lastUpdated: new Date().toISOString(),
      regions: regionRiskMap
    };

    fs.writeFileSync('fire_risk.json', JSON.stringify(output, null, 2));
    console.log('Successfully updated fire_risk.json');
  } catch (error) {
    console.error('Scraping failed:', error);
    process.exit(1);
  }
}

scrape();