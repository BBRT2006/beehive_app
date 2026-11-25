const fs = require('fs');
const puppeteer = require('puppeteer');
const Jimp = require('jimp');
const XLSX = require('xlsx');

const MAP_URL = 'https://civilprotection.gov.gr/xartis';
const ARCHIVE_URL = 'https://civilprotection.gov.gr/arxeio-imerision-xartwn';
const COORDINATES_FILE =
  './fire_hazard_scraper_coordinates_corrected.xlsx';
const REFERENCE_WIDTH = 1384;
const REFERENCE_HEIGHT = 1453;
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/122.0.0.0 Safari/537.36';

async function downloadMapImage(page, imageUrl) {
  const response = await fetch(imageUrl, {
    headers: {
      Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      Referer: MAP_URL,
      'User-Agent': USER_AGENT
    }
  });

  if (response.ok) {
    const image = Buffer.from(await response.arrayBuffer());
    if (isJpeg(image)) {
      return image;
    }

    console.warn(
      'Direct image response was not a JPEG; retrying in browser.'
    );
  } else {
    console.warn(
      `Direct image download returned ${response.status}; retrying in browser.`
    );
  }

  await page.setExtraHTTPHeaders({
    Referer: MAP_URL
  });

  const browserResponse = await page.goto(imageUrl, {
    waitUntil: 'domcontentloaded',
    timeout: 90000
  });

  if (!browserResponse || !browserResponse.ok()) {
    const status = browserResponse
      ? browserResponse.status()
      : 'no response';
    throw new Error(`Αποτυχία λήψης χάρτη: ${status}`);
  }

  const image = await browserResponse.buffer();
  if (!isJpeg(image)) {
    throw new Error('Η ληφθείσα εικόνα χάρτη δεν είναι έγκυρο JPEG.');
  }

  return image;
}

function isJpeg(buffer) {
  return (
    buffer.length >= 3 &&
    buffer[0] === 0xff &&
    buffer[1] === 0xd8 &&
    buffer[2] === 0xff
  );
}

function normalizeGreek(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/Δ\.Υ\./gi, '')
    .replace(/[^a-zA-Z0-9α-ωΑ-Ω]/g, '')
    .toUpperCase();
}

function getRiskLevel(r, g, b) {
  if (r > 180 && g < 100 && b < 100) return 5;
  if (r > 180 && g >= 80 && g < 190 && b < 130) return 4;
  if (r > 180 && g > 170 && b < 170) return 3;
  if (b > 140 && r < 190 && g < 220) return 2;
  if (g > 130 && r < 180 && b < 180) return 1;
  return 2;
}

function getRiskName(level) {
  return {
    1: 'Χαμηλή',
    2: 'Μέση',
    3: 'Υψηλή',
    4: 'Πολύ Υψηλή',
    5: 'Κατάσταση Συναγερμού'
  }[level] || 'Άγνωστο';
}

function loadForestServicePoints() {
  const workbook = XLSX.readFile(COORDINATES_FILE);
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(sheet, { defval: null });
  const points = [];

  for (const row of rows) {
    const name = String(row['ΟΝΟΜΑ'] || '').trim();
    const x = Number(row['X']);
    const y = Number(row['Y']);

    if (!name || !Number.isFinite(x) || !Number.isFinite(y)) continue;

    points.push({ name, x, y });
  }

  if (points.length === 0) {
    throw new Error('Δεν βρέθηκαν έγκυρες Δ.Υ. συντεταγμένες στο Excel.');
  }

  return points;
}

function extractMapDate(text) {
  const value = String(text || '').split('?')[0];
  const shortMatch = value.match(
    /(?:^|\/)(\d{2})(\d{2})(\d{2})(?:[_-]0)?(?:\.(?:jpg|jpeg|png|webp))$/i
  );
  if (shortMatch) {
    return `20${shortMatch[1]}-${shortMatch[2].padStart(2, '0')}-${shortMatch[3].padStart(2, '0')}`;
  }

  const longMatch = value.match(
    /(?:^|\/)(\d{4})(\d{2})(\d{2})(?:\.(?:jpg|jpeg|png|webp))$/i
  );
  if (longMatch) {
    return `${longMatch[1]}-${longMatch[2].padStart(2, '0')}-${longMatch[3].padStart(2, '0')}`;
  }

  const match = String(text || '').match(
    /\b(\d{1,2})[\/.-](\d{1,2})[\/.-](20\d{2})\b/
  );
  if (!match) return null;

  const day = match[1].padStart(2, '0');
  const month = match[2].padStart(2, '0');
  return `${match[3]}-${month}-${day}`;
}

async function findDirectMapImage() {
  const today = new Date();

  for (let offset = 0; offset <= 14; offset++) {
    const date = new Date(today);
    date.setUTCDate(today.getUTCDate() - offset);

    const year = date.getUTCFullYear();
    const month = String(date.getUTCMonth() + 1).padStart(2, '0');
    const day = String(date.getUTCDate()).padStart(2, '0');
    const shortYear = String(year).slice(-2);
    const base =
      `https://civilprotection.gov.gr/sites/default/files/` +
      `${year}-${month}/`;
    const filenames = [
      `${shortYear}${month}${day}.jpg`,
      `${shortYear}${month}${day}_0.jpg`,
      `${shortYear}${month}${day}-0.jpg`,
      `${year}${month}${day}.jpg`,
      `${shortYear}${month}${day}.jpeg`,
      `${shortYear}${month}${day}.png`
    ];

    for (const filename of filenames) {
      const url = `${base}${filename}`;
      try {
        const response = await fetch(url);
        if (response.ok) {
          return { text: filename, href: url };
        }
      } catch (_) {}
    }
  }

  return null;
}

function getRiskFromArea(image, centerX, centerY, radius = 5) {
  const counts = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };

  for (let y = centerY - radius; y <= centerY + radius; y++) {
    for (let x = centerX - radius; x <= centerX + radius; x++) {
      if (
        x < 0 ||
        y < 0 ||
        x >= image.bitmap.width ||
        y >= image.bitmap.height
      ) continue;

      const rgba = Jimp.intToRGBA(image.getPixelColor(x, y));
      counts[getRiskLevel(rgba.r, rgba.g, rgba.b)]++;
    }
  }

  let risk = 2;
  let highestCount = -1;
  for (const level of [1, 2, 3, 4, 5]) {
    if (counts[level] > highestCount) {
      highestCount = counts[level];
      risk = level;
    }
  }

  return { risk, counts };
}

async function gotoWithRetry(page, url) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return await page.goto(url, {
        waitUntil: 'domcontentloaded',
        timeout: 90000
      });
    } catch (error) {
      lastError = error;
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
  throw lastError;
}

async function scrape() {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath:
      process.env.PUPPETEER_EXECUTABLE_PATH ||
      (fs.existsSync('/usr/bin/google-chrome')
        ? '/usr/bin/google-chrome'
        : undefined),
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  try {
    const page = await browser.newPage();
    await page.setUserAgent(USER_AGENT);

    let mapCandidate = null;
    try {
      await gotoWithRetry(page, MAP_URL);
      mapCandidate = await page.evaluate(() => {
      const elements = [
        ...document.querySelectorAll('a'),
        ...document.querySelectorAll('img')
      ];

      for (const element of elements) {
        const href =
          element.href ||
          element.src ||
          element.dataset.src ||
          '';
        if (/\.(jpg|jpeg|png|webp)$/i.test(href.split('?')[0])) {
          return {
            text:
              (element.innerText ||
                element.alt ||
                element.title ||
                '').trim(),
            href
          };
        }
      }
      return null;
      });
    } catch (_) {}

    if (!mapCandidate) {
      try {
        await gotoWithRetry(page, ARCHIVE_URL);
        mapCandidate = await page.evaluate(() => {
        const link = Array.from(document.querySelectorAll('a')).find(a =>
          /ημερήσιος χάρτης πρόβλεψης/i.test(a.innerText || '')
        );
        return link
          ? { text: (link.innerText || '').trim(), href: link.href }
          : null;
        });

        if (mapCandidate) {
          await gotoWithRetry(page, mapCandidate.href);
          mapCandidate = await page.evaluate(previous => {
            const elements = [
              ...document.querySelectorAll('a'),
              ...document.querySelectorAll('img')
            ];
            const jpg = elements.find(element => {
              const href =
                element.href ||
                element.src ||
                element.dataset.src ||
                '';
              return /\.(jpg|jpeg|png|webp)$/i.test(href.split('?')[0]);
            });
            if (!jpg) return null;
            return {
              text: previous.text,
              href:
                jpg.href ||
                jpg.src ||
                jpg.dataset.src
            };
          }, mapCandidate);
        }
      } catch (_) {}
    }

    if (!mapCandidate) {
      mapCandidate = await findDirectMapImage();
    }

    if (!mapCandidate) {
      throw new Error('Δεν βρέθηκε η εικόνα του τελευταίου χάρτη.');
    }

    const mapDate =
      extractMapDate(mapCandidate.text) ||
      extractMapDate(mapCandidate.href);

    if (!mapDate) {
      throw new Error('Δεν μπόρεσε να προσδιοριστεί η ημερομηνία του χάρτη.');
    }

    console.log(`Downloading map image: ${mapCandidate.href}`);
    const image = await Jimp.read(
      await downloadMapImage(page, mapCandidate.href)
    );
    const scaleX = image.bitmap.width / REFERENCE_WIDTH;
    const scaleY = image.bitmap.height / REFERENCE_HEIGHT;

    const forestServices = {};
    const forestServiceDetails = {};

    for (const point of loadForestServicePoints()) {
      const x = Math.round(point.x * scaleX);
      const y = Math.round(point.y * scaleY);
      const result = getRiskFromArea(image, x, y, 5);

      forestServices[point.name] = result.risk;
      forestServiceDetails[point.name] = {
        name: point.name,
        x,
        y,
        referenceX: point.x,
        referenceY: point.y,
        risk: result.risk,
        riskName: getRiskName(result.risk),
        pixelCounts: result.counts
      };

      console.log(
        `Δ.Υ. ${point.name}: ${result.risk} - ` +
        `${getRiskName(result.risk)}`
      );
    }

    const output = {
      lastUpdated: new Date().toISOString(),
      mapDate,
      sourceUrl: mapCandidate.href,
      imageUrl: mapCandidate.href,
      imageSize: {
        width: image.bitmap.width,
        height: image.bitmap.height
      },
      forest_service_count: Object.keys(forestServices).length,
      forest_services: forestServices,
      forest_service_details: forestServiceDetails
    };

    fs.writeFileSync(
      'fire_risk.json',
      JSON.stringify(output, null, 2),
      'utf8'
    );

    console.log(
      `✅ fire_risk.json ενημερώθηκε: ` +
      `${Object.keys(forestServices).length} Δ.Υ.`
    );
  } catch (error) {
    console.error(`❌ ${error.message}`);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

if (require.main === module) {
  scrape();
}

module.exports = {
  extractMapDate,
  findDirectMapImage,
  getRiskLevel
};
