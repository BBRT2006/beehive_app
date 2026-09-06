const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');

async function scrape() {
  // 1. Πλήρης λίστα με όλους τους Νομούς / Μεγάλα νησιά
  const regions = [
    "Έβρος", "Ροδόπη", "Ξάνθη", "Καβάλα", "Δράμα", "Σέρρες", "Κιλκίς",
    "Πέλλα", "Ημαθία", "Θεσσαλονίκη", "Χαλκιδική", "Φλώρινα", "Κοζάνη",
    "Καστοριά", "Γρεβενά", "Ιωάννινα", "Άρτα", "Θεσπρωτία", "Πρέβεζα",
    "Λάρισα", "Μαγνησία", "Τρίκαλα", "Καρδίτσα", "Φθιώτιδα", "Εύβοια",
    "Βοιωτία", "Φωκίδα", "Ευρυτανία", "Αιτωλοακαρνανία", "Αττική", "Πειραιάς",
    "Αχαΐα", "Ηλεία", "Αρκαδία", "Κορινθία", "Αργολίδα", "Μεσσηνία", "Λακωνία",
    "Κέρκυρα", "Κεφαλληνία", "Κεφαλονιά", "Ζάκυνθος", "Λευκάδα", "Ιθάκη",
    "Λέσβος", "Χίος", "Σάμος", "Λήμνος", "Ικαρία", "Κυκλάδες", "Δωδεκάνησα",
    "Ρόδος", "Κως", "Κάρπαθος", "Σποράδες", "Θάσος", "Σαμοθράκη",
    "Ηράκλειο", "Χανιά", "Ρέθυμνο", "Λασίθι"
  ];

  // Default baseline map (Ορίζουμε την κατηγορία 2 ως προεπιλογή για όλους)
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
      const text = detail$('body').text().toLowerCase();

      regions.forEach((region) => {
        const lowerRegion = region.toLowerCase();
        // Regex: Ψάχνει την περιοχή ως ολόκληρη λέξη, για να μην πάρει το "Κως" μέσα από τη λέξη "όπως"
        const regex = new RegExp(`(?:^|\\s|-|\\.|,)${lowerRegion}(?:$|\\s|-|\\.|,)`, 'i');

        if (regex.test(text)) {
          if (text.includes('κατηγορία 5') || text.includes('κατάσταση συναγερμού')) {
            regionRiskMap[region] = 5;
          } else if (text.includes('κατηγορία 4') || text.includes('πολύ υψηλός')) {
            regionRiskMap[region] = 4;
          } else if ((text.includes('κατηγορία 3') || text.includes('υψηλός κίνδυνος')) && regionRiskMap[region] < 3) {
            regionRiskMap[region] = 3;
          }
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