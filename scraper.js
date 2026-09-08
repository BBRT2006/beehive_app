const puppeteer = require('puppeteer');
const fs = require('fs');
const Tesseract = require('tesseract.js');

async function scrape() {
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

  let sourceUrl = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn?page=0%2C0';

  console.log('Ανοίγει ο αόρατος browser...');
  const browser = await puppeteer.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'] 
  });
  const page = await browser.newPage();
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');

  try {
    console.log('Πλοήγηση στη λίστα αρχείου της Πολιτικής Προστασίας...');
    await page.goto(sourceUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Παίρνουμε τα 2 πιο πρόσφατα links από τη λίστα
    const topTwoLinks = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('a'));
      const mapLinks = links
        .filter(a => a.innerText.toLowerCase().includes('χάρτ') || a.href.toLowerCase().includes('xart'))
        .map(a => a.href);
      // Αφαιρούμε τα διπλότυπα και κρατάμε τα 2 πρώτα
      return [...new Set(mapLinks)].slice(0, 2);
    });

    console.log('Βρέθηκαν τα 2 τελευταία links:', topTwoLinks);

    // Προσωρινό αντικείμενο για να κρατήσουμε τα δεδομένα και των 2 ημερών
    let daysData = [];

    // Για κάθε ένα από τα 2 links...
    for (let i = 0; i < topTwoLinks.length; i++) {
      console.log(`\n=== Επεξεργασία Link ${i + 1} ===`);
      console.log(`Άνοιγμα: ${topTwoLinks[i]}`);
      
      await page.goto(topTwoLinks[i], { waitUntil: 'domcontentloaded', timeout: 30000 });

      const imageUrl = await page.evaluate(() => {
        const img = document.querySelector('a[href$=".jpg"], a[href$=".png"], .field--type-image img');
        return img ? (img.href || img.src) : null;
      });

      if (imageUrl) {
        console.log('Βρέθηκε εικόνα χάρτη:', imageUrl);
        console.log('Ξεκινάει η Τεχνητή Νοημοσύνη (OCR)...');

        const { data: { text } } = await Tesseract.recognize(imageUrl, 'ell');
        console.log(`--- ΚΕΙΜΕΝΟ ΑΠΟ ΕΙΚΟΝΑ ${i + 1} ---`);
        console.log(text.substring(0, 300) + '...'); 
        
        let regionRiskMap = {};
        regions.forEach((r) => { regionRiskMap[r] = 2; }); // Προεπιλογή 2

        const lowerText = text.toLowerCase();
        regions.forEach((region) => {
          const regex = new RegExp(`(?:^|\\s|-|\\.|,)${region.toLowerCase()}(?:$|\\s|-|\\.|,)`, 'i');
          if (regex.test(lowerText)) {
             if (lowerText.includes('κατηγορία 5') || lowerText.includes('συναγερμού')) regionRiskMap[region] = 5;
             else if (lowerText.includes('κατηγορία 4') || lowerText.includes('πολύ υψηλός')) regionRiskMap[region] = 4;
             else if (lowerText.includes('κατηγορία 3') || lowerText.includes('υψηλός')) regionRiskMap[region] = 3;
          }
        });

        daysData.push({ url: topTwoLinks[i], regions: regionRiskMap });
      } else {
        console.warn(`Δεν βρέθηκε εικόνα στο Link ${i + 1}`);
      }
    }

    // Αποθήκευση - Προς το παρόν γράφουμε τα δεδομένα της πρώτης εικόνας 
    // στο fire_risk.json για να μη σπάσει το Flutter app σου
    if (daysData.length > 0) {
      const output = {
        lastUpdated: new Date().toISOString(),
        sourceUrl: daysData[0].url,
        regions: daysData[0].regions
      };
      fs.writeFileSync('fire_risk.json', JSON.stringify(output, null, 2));
      console.log('\nΤο fire_risk.json ενημερώθηκε!');
    }

  } catch (err) {
    console.error('Σφάλμα κατά την πλοήγηση:', err.message);
  } finally {
    await browser.close();
  }
}
scrape();