const puppeteer = require('puppeteer');
const fs = require('fs');
const Jimp = require('jimp'); // Το νέο μας εργαλείο για χρώματα (Pixels)

// ΕΝΔΕΙΚΤΙΚΕΣ ΣΥΝΤΕΤΑΓΜΕΝΕΣ (X, Y) ΓΙΑ ΚΑΘΕ ΝΟΜΟ ΣΤΟΝ ΧΑΡΤΗ
// Θα πρέπει να τις "καλιμπράρεις" ανοίγοντας μια εικόνα χάρτη στη Ζωγραφική (MS Paint).
const regionPixels = {
  "Αττική": { x: 550, y: 650 },
  "Έβρος": { x: 740, y: 150 },
  "Χανιά": { x: 480, y: 920 },
  "Θεσσαλονίκη": { x: 490, y: 250 },
  "Αχαΐα": { x: 380, y: 610 }
  // Στην πορεία θα προσθέσεις και τους υπόλοιπους νομούς εδώ...
};

// Συνάρτηση που μετατρέπει το χρώμα (RGB) σε κατηγορία κινδύνου (1-5)
function getRiskLevel(r, g, b) {
  // Κατηγορία 5: Κόκκινο (Υψηλό Red, Χαμηλό Green/Blue)
  if (r > 200 && g < 100 && b < 100) return 5;
  
  // Κατηγορία 4: Πορτοκαλί (Υψηλό Red, Μέτριο Green, Χαμηλό Blue)
  if (r > 200 && g > 100 && g < 180 && b < 100) return 4;
  
  // Κατηγορία 3: Κίτρινο (Υψηλό Red και Green, Χαμηλό Blue)
  if (r > 200 && g > 200 && b < 150) return 3;
  
  // Κατηγορία 2: Μπλε (Υψηλό Blue, χαμηλό Red/Green - Το default της Πολιτικής Προστασίας)
  if (b > 150 && r < 150) return 2;
  
  // Κατηγορία 1: Πράσινο
  if (g > 150 && r < 150 && b < 150) return 1;
  
  return 2; // Προεπιλογή αν το χρώμα είναι κάτι άσχετο (π.χ. μαύρη γραμμή συνόρων)
}

async function scrape() {
  let sourceUrl = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn?page=0%2C0';

  console.log('Ανοίγει ο αόρατος browser...');
  const browser = await puppeteer.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'] 
  });
  const page = await browser.newPage();
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');

  try {
    await page.goto(sourceUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    const topTwoLinks = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('a'));
      const mapLinks = links
        .filter(a => a.innerText.toLowerCase().includes('χάρτ') || a.href.toLowerCase().includes('xart'))
        .map(a => a.href);
      return [...new Set(mapLinks)].slice(0, 2);
    });

    let daysData = [];

    for (let i = 0; i < topTwoLinks.length; i++) {
      console.log(`\n=== Επεξεργασία Χάρτη ${i + 1} ===`);
      await page.goto(topTwoLinks[i], { waitUntil: 'domcontentloaded', timeout: 30000 });

      const imageUrl = await page.evaluate(() => {
        const img = document.querySelector('a[href$=".jpg"], a[href$=".png"], .field--type-image img');
        return img ? (img.href || img.src) : null;
      });

      if (imageUrl) {
        console.log('Κατέβασμα εικόνας χάρτη...', imageUrl);
        const viewSource = await page.goto(imageUrl);
        const imageBuffer = await viewSource.buffer();

        // Διαβάζουμε την εικόνα με το Jimp
        const image = await Jimp.read(imageBuffer);
        let regionRiskMap = {};

        console.log('Ανάλυση χρωμάτων ανά νομό...');
        
        // Για κάθε νομό που έχουμε καταχωρήσει τις συντεταγμένες του...
        for (const [region, coords] of Object.entries(regionPixels)) {
          // Παίρνουμε το χρώμα (Δεκαεξαδικό/HEX) του συγκεκριμένου pixel
          const hex = image.getPixelColor(coords.x, coords.y);
          // Το μετατρέπουμε σε RGBA (Κόκκινο, Πράσινο, Μπλε, Άλφα)
          const rgba = Jimp.intToRGBA(hex); 
          
          // Βρίσκουμε την κατηγορία κινδύνου βάσει του χρώματος
          const riskLevel = getRiskLevel(rgba.r, rgba.g, rgba.b);
          regionRiskMap[region] = riskLevel;

          console.log(`- ${region}: Βρέθηκε χρώμα RGB(${rgba.r}, ${rgba.g}, ${rgba.b}) -> Κατηγορία Κινδύνου: ${riskLevel}`);
        }

        daysData.push({ url: topTwoLinks[i], regions: regionRiskMap });
      }
    }

    if (daysData.length > 0) {
      const output = {
        lastUpdated: new Date().toISOString(),
        sourceUrl: daysData[0].url,
        regions: daysData[0].regions
      };
      fs.writeFileSync('fire_risk.json', JSON.stringify(output, null, 2));
      console.log('\nΤο fire_risk.json ενημερώθηκε επιτυχώς με βάση τα χρώματα!');
    }

  } catch (err) {
    console.error('Σφάλμα:', err.message);
  } finally {
    await browser.close();
  }
}

scrape();