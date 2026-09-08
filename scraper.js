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

  const regionRiskMap = {};
  regions.forEach((r) => { regionRiskMap[r] = 2; });

  let sourceUrl = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn';

  console.log('Ανοίγει ο αόρατος browser...');
  const browser = await puppeteer.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'] 
  });
  const page = await browser.newPage();
  
  // Κάνουμε τον browser να φαίνεται σαν κανονικό Chrome
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');

  try {
    console.log('Πλοήγηση στη σελίδα της Πολιτικής Προστασίας...');
    await page.goto(sourceUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Βρίσκουμε το link για τον σημερινό/αυριανό χάρτη
    const linkHref = await page.evaluate(() => {
      const link = document.querySelector('a[href*="xartis-provlepsis"], a[href*="imerisios-xartis"], .views-row a');
      return link ? link.href : null;
    });

    if (linkHref) {
      console.log('Βρέθηκε η ανακοίνωση:', linkHref);
      await page.goto(linkHref, { waitUntil: 'domcontentloaded', timeout: 30000 });

      // Βρίσκουμε την εικόνα του χάρτη (jpg, png ή γενικά image)
      const imageUrl = await page.evaluate(() => {
        const img = document.querySelector('a[href$=".jpg"], a[href$=".png"]') || document.querySelector('img');
        return img ? (img.href || img.src) : null;
      });

      if (imageUrl) {
        console.log('Βρέθηκε εικόνα χάρτη:', imageUrl);
        console.log('Ξεκινάει η Τεχνητή Νοημοσύνη (OCR)...');

        const { data: { text } } = await Tesseract.recognize(
          imageUrl,
          'ell', 
          { logger: m => console.log(`Πρόοδος OCR: ${m.status} ${Math.round(m.progress * 100)}%`) }
        );

        console.log('\n--- ΚΕΙΜΕΝΟ ΠΟΥ ΔΙΑΒΑΣΕ ΤΟ AI ---');
        console.log(text.substring(0, 500) + '...'); 
        console.log('---------------------------------\n');

        const lowerText = text.toLowerCase();

        regions.forEach((region) => {
          const lowerRegion = region.toLowerCase();
          const regex = new RegExp(`(?:^|\\s|-|\\.|,)${lowerRegion}(?:$|\\s|-|\\.|,)`, 'i');

          if (regex.test(lowerText)) {
             if (lowerText.includes('κατηγορία 5') || lowerText.includes('συναγερμού')) {
               regionRiskMap[region] = 5;
             } else if (lowerText.includes('κατηγορία 4') || lowerText.includes('πολύ υψηλός')) {
               regionRiskMap[region] = 4;
             } else if (lowerText.includes('κατηγορία 3') || lowerText.includes('υψηλός')) {
               regionRiskMap[region] = 3;
             }
          }
        });
      } else {
        console.warn('Δεν βρέθηκε εικόνα χάρτη μέσα στην ανακοίνωση.');
      }
    } else {
      console.warn('Δεν βρέθηκε ανακοίνωση χάρτη στην αρχική.');
    }
  } catch (err) {
    console.error('Σφάλμα κατά την πλοήγηση:', err.message);
  } finally {
    await browser.close(); // Κλείνουμε τον browser για να μην τρώει μνήμη
  }

  const output = {
    lastUpdated: new Date().toISOString(),
    sourceUrl: sourceUrl,
    regions: regionRiskMap
  };

  fs.writeFileSync('fire_risk.json', JSON.stringify(output, null, 2));
  console.log('Το fire_risk.json ενημερώθηκε!');
}

scrape();