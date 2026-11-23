const puppeteer = require('puppeteer');
const fs = require('fs');
const Jimp = require('jimp');
const XLSX = require('xlsx');


// ============================================================
// CONFIG
// ============================================================

const MAP_URL =
  'https://civilprotection.gov.gr/xartis';

const ARCHIVE_URL =
  'https://civilprotection.gov.gr/arxeio-imerision-xartwn?page=0%2C0';


// Official Regional Units GIS service
const REGIONAL_UNITS_URL =
  'https://geohub.necca.gov.gr/server/rest/services/' +
  'ELBIOS-EXTERNAL_DATA/perifereiakes_enotites/' +
  'FeatureServer/0/query';


// Reference dimensions of the map used for the coordinates below.
// The scraper automatically scales the coordinates if the image
// dimensions change.

const REFERENCE_WIDTH = 1384;
const REFERENCE_HEIGHT = 1453;

const FOREST_SERVICES_XLSX =
  './fire_hazard_scraper_coordinates_corrected.xlsx';

function loadForestServicePoints(filePath) {
  const workbook = XLSX.readFile(filePath);
  const sheetName = workbook.SheetNames[0];
  const rows = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {
    defval: null
  });

  const points = {};
  for (const row of rows) {
    const name =
      String(row['ΟΝΟΜΑ'] || '').trim();
    const x = Number(row['X']);
    const y = Number(row['Y']);

    if (!name || !Number.isFinite(x) || !Number.isFinite(y)) {
      continue;
    }

    points[name] = { x, y };
  }

  if (Object.keys(points).length === 0) {
    throw new Error(
      'Το Excel δεν περιέχει έγκυρες Δ.Υ. συντεταγμένες.'
    );
  }

  return points;
}


// ============================================================
// ΠΕΡΙΦΕΡΕΙΑΚΕΣ ΕΝΟΤΗΤΕΣ
// ============================================================
//
// x / y = pixel position inside the official fire map.
//
// These are reference points inside each PE.
// They are automatically scaled to the actual image size.
//
// ============================================================

const REGION_POINTS = {

  // ----------------------------------------------------------
  // ΑΝΑΤΟΛΙΚΗ ΜΑΚΕΔΟΝΙΑ & ΘΡΑΚΗ
  // ----------------------------------------------------------

  "Έβρου": {
    x: 790,
    y: 290
  },

  "Ροδόπης": {
    x: 725,
    y: 290
  },

  "Ξάνθης": {
    x: 675,
    y: 300
  },

  "Καβάλας": {
    x: 625,
    y: 330
  },

  "Θάσου": {
    x: 680,
    y: 360
  },

  "Δράμας": {
    x: 610,
    y: 290
  },


  // ----------------------------------------------------------
  // ΚΕΝΤΡΙΚΗ ΜΑΚΕΔΟΝΙΑ
  // ----------------------------------------------------------

  "Ημαθίας": {
    x: 410,
    y: 420
  },

  "Θεσσαλονίκης": {
    x: 520,
    y: 360
  },

  "Κιλκίς": {
    x: 500,
    y: 340
  },

  "Πέλλας": {
    x: 445,
    y: 380
  },

  "Πιερίας": {
    x: 400,
    y: 475
  },

  "Σερρών": {
    x: 550,
    y: 320
  },

  "Χαλκιδικής": {
    x: 565,
    y: 405
  },


  // ----------------------------------------------------------
  // ΔΥΤΙΚΗ ΜΑΚΕΔΟΝΙΑ
  // ----------------------------------------------------------

  "Γρεβενών": {
    x: 360,
    y: 540
  },

  "Καστοριάς": {
    x: 250,
    y: 510
  },

  "Κοζάνης": {
    x: 350,
    y: 470
  },

  "Φλώρινας": {
    x: 280,
    y: 430
  },


  // ----------------------------------------------------------
  // ΗΠΕΙΡΟΣ
  // ----------------------------------------------------------

  "Άρτας": {
    x: 315,
    y: 680
  },

  "Θεσπρωτίας": {
    x: 210,
    y: 560
  },

  "Ιωαννίνων": {
    x: 300,
    y: 600
  },

  "Πρέβεζας": {
    x: 240,
    y: 650
  },


  // ----------------------------------------------------------
  // ΘΕΣΣΑΛΙΑ
  // ----------------------------------------------------------

  "Καρδίτσας": {
    x: 410,
    y: 620
  },

  "Λάρισας": {
    x: 450,
    y: 570
  },

  "Μαγνησίας": {
    x: 505,
    y: 590
  },

  "Σποράδων": {
    x: 590,
    y: 600
  },

  "Τρικάλων": {
    x: 350,
    y: 600
  },


  // ----------------------------------------------------------
  // ΙΟΝΙΑ ΝΗΣΙΑ
  // ----------------------------------------------------------

  "Ζακύνθου": {
    x: 200,
    y: 820
  },

  "Κέρκυρας": {
    x: 85,
    y: 530
  },

  "Κεφαλληνίας": {
    x: 180,
    y: 720
  },

  "Λευκάδας": {
    x: 180,
    y: 660
  },

  "Ιθάκης": {
    x: 205,
    y: 735
  },


  // ----------------------------------------------------------
  // ΔΥΤΙΚΗ ΕΛΛΑΔΑ
  // ----------------------------------------------------------

  "Αιτωλοακαρνανίας": {
    x: 290,
    y: 820
  },

  "Αχαΐας": {
    x: 300,
    y: 800
  },

  "Ηλείας": {
    x: 290,
    y: 840
  },


  // ----------------------------------------------------------
  // ΣΤΕΡΕΑ ΕΛΛΑΔΑ
  // ----------------------------------------------------------

  "Βοιωτίας": {
    x: 510,
    y: 730
  },

  "Εύβοιας": {
    x: 590,
    y: 780
  },

  "Ευρυτανίας": {
    x: 360,
    y: 720
  },

  "Φθιώτιδας": {
    x: 450,
    y: 700
  },

  "Φωκίδας": {
    x: 440,
    y: 740
  },


  // ----------------------------------------------------------
  // ΑΤΤΙΚΗ
  // ----------------------------------------------------------

  "Κεντρικού Τομέα Αθηνών": {
    x: 575,
    y: 770
  },

  "Βορείου Τομέα Αθηνών": {
    x: 570,
    y: 745
  },

  "Νοτίου Τομέα Αθηνών": {
    x: 580,
    y: 805
  },

  "Δυτικού Τομέα Αθηνών": {
    x: 550,
    y: 775
  },

  "Ανατολικής Αττικής": {
    x: 625,
    y: 770
  },

  "Δυτικής Αττικής": {
    x: 500,
    y: 775
  },

  "Πειραιώς": {
    x: 550,
    y: 825
  },

  "Νήσων": {
    x: 600,
    y: 850
  },


  // ----------------------------------------------------------
  // ΠΕΛΟΠΟΝΝΗΣΟΣ
  // ----------------------------------------------------------

  "Αργολίδας": {
    x: 500,
    y: 830
  },

  "Αρκαδίας": {
    x: 380,
    y: 840
  },

  "Κορινθίας": {
    x: 450,
    y: 790
  },

  "Λακωνίας": {
    x: 440,
    y: 950
  },

  "Μεσσηνίας": {
    x: 330,
    y: 940
  },


  // ----------------------------------------------------------
  // ΒΟΡΕΙΟ ΑΙΓΑΙΟ
  // ----------------------------------------------------------

  "Λέσβου": {
    x: 870,
    y: 600
  },

  "Λήμνου": {
    x: 750,
    y: 480
  },

  "Χίου": {
    x: 870,
    y: 720
  },

  "Σάμου": {
    x: 940,
    y: 840
  },

  "Ικαρίας": {
    x: 780,
    y: 860
  },


  // ----------------------------------------------------------
  // ΝΟΤΙΟ ΑΙΓΑΙΟ
  // ----------------------------------------------------------

  "Άνδρου": {
    x: 730,
    y: 720
  },

  "Θήρας": {
    x: 780,
    y: 950
  },

  "Καλύμνου": {
    x: 900,
    y: 900
  },

  "Καρπάθου": {
    x: 990,
    y: 1010
  },

  "Κέας - Κύθνου": {
    x: 700,
    y: 850
  },

  "Κω": {
    x: 900,
    y: 950
  },

  "Μήλου": {
    x: 690,
    y: 880
  },

  "Μυκόνου": {
    x: 800,
    y: 850
  },

  "Νάξου": {
    x: 800,
    y: 900
  },

  "Πάρου": {
    x: 760,
    y: 880
  },

  "Ρόδου": {
    x: 1025,
    y: 975
  },

  "Σύρου": {
    x: 745,
    y: 825
  },

  "Τήνου": {
    x: 760,
    y: 780
  },


  // ----------------------------------------------------------
  // ΚΡΗΤΗ
  // ----------------------------------------------------------

  "Ηρακλείου": {
    x: 735,
    y: 1250
  },

  "Λασιθίου": {
    x: 820,
    y: 1250
  },

  "Ρεθύμνης": {
    x: 670,
    y: 1230
  },

  "Χανίων": {
    x: 600,
    y: 1210
  }

};


// ============================================================
// NORMALIZE GREEK NAMES
// ============================================================

function normalizeGreek(text) {

  if (!text) {
    return '';
  }

  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ΠΕΡΙΦΕΡΕΙΑΚΗ ΕΝΟΤΗΤΑ/gi, '')
    .replace(/ΠΕ/gi, '')
    .replace(/[()]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

}


// ============================================================
// RISK COLOR
// ============================================================

function getRiskLevel(r, g, b) {

  // RED = 5
  if (
    r > 180 &&
    g < 100 &&
    b < 100
  ) {
    return 5;
  }

  // ORANGE = 4
  if (
    r > 180 &&
    g >= 80 &&
    g < 190 &&
    b < 130
  ) {
    return 4;
  }

  // YELLOW = 3
  if (
    r > 180 &&
    g > 170 &&
    b < 170
  ) {
    return 3;
  }

  // BLUE = 2
  if (
    b > 140 &&
    r < 190 &&
    g < 220
  ) {
    return 2;
  }

  // GREEN = 1
  if (
    g > 130 &&
    r < 180 &&
    b < 180
  ) {
    return 1;
  }

  // Default
  return 2;
}


// ============================================================
// RISK NAME
// ============================================================

function getRiskName(level) {

  switch (level) {

    case 1:
      return 'Χαμηλή';

    case 2:
      return 'Μέση';

    case 3:
      return 'Υψηλή';

    case 4:
      return 'Πολύ Υψηλή';

    case 5:
      return 'Κατάσταση Συναγερμού';

    default:
      return 'Άγνωστο';
  }

}


// ============================================================
// AREA SAMPLING
// ============================================================

function getRiskFromArea(
  image,
  centerX,
  centerY,
  radius = 5
) {

  const counts = {
    1: 0,
    2: 0,
    3: 0,
    4: 0,
    5: 0
  };


  for (
    let y = centerY - radius;
    y <= centerY + radius;
    y++
  ) {

    for (
      let x = centerX - radius;
      x <= centerX + radius;
      x++
    ) {

      if (
        x < 0 ||
        y < 0 ||
        x >= image.bitmap.width ||
        y >= image.bitmap.height
      ) {
        continue;
      }


      const color =
        image.getPixelColor(x, y);


      const rgba =
        Jimp.intToRGBA(color);


      const risk =
        getRiskLevel(
          rgba.r,
          rgba.g,
          rgba.b
        );


      counts[risk]++;
    }
  }


  let bestRisk = 2;
  let bestCount = -1;


  for (
    const [risk, count]
    of Object.entries(counts)
  ) {

    if (count > bestCount) {

      bestCount = count;
      bestRisk = Number(risk);

    }

  }


  return {
    risk: bestRisk,
    counts: counts
  };

}


// ============================================================
// GET OFFICIAL REGIONAL UNITS
// ============================================================

async function getRegionalUnits() {

  const url =
    REGION_UNITS_QUERY_URL();


  console.log(
    'Λήψη επίσημων Περιφερειακών Ενοτήτων...'
  );


  const response =
    await fetch(url);


  if (!response.ok) {

    throw new Error(
      `GIS request failed: ${response.status}`
    );

  }


  const data =
    await response.json();


  if (!data.features) {

    throw new Error(
      'Το GIS service δεν επέστρεψε features.'
    );

  }


  return data.features;

}


function REGION_UNITS_QUERY_URL() {

  const params =
    new URLSearchParams({

      where: '1=1',

      outFields:
        'CODE,NAME_GR,NAME_ENG',

      returnGeometry:
        'false',

      f:
        'geojson'

    });


  return (
    `${REGIONAL_UNITS_URL}?${params.toString()}`
  );

}


// ============================================================
// FIND OFFICIAL PE
// ============================================================

function findOfficialRegion(
  regionName,
  features
) {

  const wanted =
    normalizeGreek(regionName);


  let best = null;


  for (
    const feature of features
  ) {

    const props =
      feature.properties || {};


    const officialName =
      normalizeGreek(
        props.NAME_GR
      );


    if (
      officialName === wanted
    ) {

      return {

        code:
          props.CODE,

        nameGr:
          props.NAME_GR,

        nameEn:
          props.NAME_ENG

      };

    }


    // Partial fallback
    if (
      officialName.includes(wanted) ||
      wanted.includes(officialName)
    ) {

      best = {

        code:
          props.CODE,

        nameGr:
          props.NAME_GR,

        nameEn:
          props.NAME_ENG

      };

    }

  }


  return best;

}


// ============================================================
// EXTRACT MAP DATE
// ============================================================

function extractMapDate(text) {

  if (!text) {
    return null;
  }


  // Look for:
  //
  // 10/09/2026
  // 09/09/2026
  //
  // The first date in the title is the date
  // the map applies to.

  const matches =
    text.match(
      /\b(\d{1,2})[\/.-](\d{1,2})[\/.-](20\d{2})\b/g
    );


  if (
    !matches ||
    matches.length === 0
  ) {

    return null;

  }


  const parts =
    matches[0].match(
      /(\d{1,2})[\/.-](\d{1,2})[\/.-](20\d{2})/
    );


  if (!parts) {
    return null;
  }


  const day =
    parts[1].padStart(2, '0');

  const month =
    parts[2].padStart(2, '0');

  const year =
    parts[3];


  return `${year}-${month}-${day}`;

}


// ============================================================
// MAIN
// ============================================================

async function scrape() {

  console.log('');
  console.log('==============================================');
  console.log('🔥 FIRE RISK SCRAPER');
  console.log('==============================================');


  const browser =
    await puppeteer.launch({

      headless: true,
      executablePath:
        process.env.PUPPETEER_EXECUTABLE_PATH ||
        (
          fs.existsSync('/usr/bin/google-chrome')
            ? '/usr/bin/google-chrome'
            : undefined
        ),

      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox'
      ]

    });


  try {

    const page =
      await browser.newPage();


    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
      'AppleWebKit/537.36 (KHTML, like Gecko) ' +
      'Chrome/122.0.0.0 Safari/537.36'
    );


    // ========================================================
    // OPEN ARCHIVE
    // ========================================================

    console.log(
      'Άνοιγμα αρχείου χαρτών...'
    );


    await page.goto(
      MAP_URL,
      {
        waitUntil: 'domcontentloaded',
        timeout: 90000
      }
    );


    // ========================================================
    // FIND LATEST MAP LINK
    // ========================================================

    let latest =
      await page.evaluate(() => {

        const candidates =
          Array.from(
            document.querySelectorAll('a, img')
          )
            .map(element => ({
              text:
                (
                  element.innerText ||
                  element.alt ||
                  element.title ||
                  ''
                ).trim(),

              href:
                element.href ||
                element.src ||
                ''
            }))
            .filter(item =>
              /\.(jpg|jpeg)$/i.test(
                item.href.split('?')[0]
              ) ||
              /χάρτ|χάρτης|fire|risk|πρόβλεψης/i.test(
                item.text
              )
            );

        return candidates.find(item =>
          /(?:^|\/)\d{6}\.(?:jpg|jpeg)$/i.test(
            item.href
          )
        ) || candidates.find(item =>
          /\.(jpg|jpeg)$/i.test(
            item.href.split('?')[0]
          )
        ) || null;
      });

    if (!latest) {
      await page.goto(
        ARCHIVE_URL,
        {
          waitUntil: 'domcontentloaded',
          timeout: 90000
        }
      );

      latest =
        await page.evaluate(() => {
          const candidates =
            Array.from(
              document.querySelectorAll('a')
            )
              .map(a => ({
                text: (a.innerText || '').trim(),
                href: a.href
              }))
              .filter(item =>
                /ημερήσιος χάρτης πρόβλεψης/i.test(
                  item.text
                )
              );

          return candidates[0] || null;
        });
    }


    if (!latest) {

      throw new Error(
        'Δεν βρέθηκε ο τελευταίος χάρτης.'
      );

    }


    console.log('');
    console.log(
      `Χάρτης: ${latest.text}`
    );

    console.log(
      `URL: ${latest.href}`
    );


    // ========================================================
    // MAP DATE
    // ========================================================

    const mapDate =
      extractMapDate(
        latest.text
      );


    if (!mapDate) {

      throw new Error(
        'Δεν μπόρεσα να βρω την ημερομηνία του χάρτη.'
      );

    }


    console.log(
      `Ημερομηνία ισχύος: ${mapDate}`
    );


    // ========================================================
    // OPEN MAP PAGE
    // ========================================================

    await page.goto(
      latest.href,
      {
        waitUntil: 'domcontentloaded',
        timeout: 90000
      }
    );


    // ========================================================
    // FIND IMAGE
    // ========================================================

    const imageUrl =
      await page.evaluate(() => {

        const links =
          Array.from(
            document.querySelectorAll('a')
          );


        const jpg =
          links.find(a =>
            /\.(jpg|jpeg|png)$/i.test(
              a.href
            )
          );


        if (jpg) {
          return jpg.href;
        }


        const img =
          document.querySelector(
            '.field--type-image img'
          );


        return img
          ? img.src
          : null;

      });


    if (!imageUrl) {

      throw new Error(
        'Δεν βρέθηκε η εικόνα του χάρτη.'
      );

    }


    console.log(
      `Image: ${imageUrl}`
    );


    // ========================================================
    // DOWNLOAD IMAGE
    // ========================================================

    const imageResponse =
      await fetch(
        imageUrl
      );


    if (!imageResponse.ok) {

      throw new Error(
        `Image download failed: ` +
        `${imageResponse.status}`
      );

    }


    const imageBuffer =
      Buffer.from(
        await imageResponse.arrayBuffer()
      );


    const image =
      await Jimp.read(
        imageBuffer
      );


    console.log(
      `Image size: ` +
      `${image.bitmap.width} x ` +
      `${image.bitmap.height}`
    );


    // ========================================================
    // SCALE COORDINATES
    // ========================================================

    const scaleX =
      image.bitmap.width /
      REFERENCE_WIDTH;


    const scaleY =
      image.bitmap.height /
      REFERENCE_HEIGHT;


    // ========================================================
    // ANALYZE FOREST SERVICES
    // ========================================================

    const forestServicePoints =
      loadForestServicePoints(
        FOREST_SERVICES_XLSX
      );

    const forestServices = {};
    const forestServiceDetails = {};

    console.log(
      `Δ.Υ. συντεταγμένες: ` +
      `${Object.keys(forestServicePoints).length}`
    );

    for (
      const [
        forestServiceName,
        referenceCoords
      ]
      of Object.entries(forestServicePoints)
    ) {
      const x =
        Math.round(
          referenceCoords.x *
          scaleX
        );

      const y =
        Math.round(
          referenceCoords.y *
          scaleY
        );

      const result =
        getRiskFromArea(
          image,
          x,
          y,
          5
        );

      forestServices[forestServiceName] =
        result.risk;

      forestServiceDetails[forestServiceName] = {
        name: forestServiceName,
        x,
        y,
        risk: result.risk,
        riskName: getRiskName(result.risk),
        pixelCounts: result.counts
      };

      console.log(
        `Δ.Υ. ${forestServiceName}: ` +
        `${result.risk} - ` +
        `${getRiskName(result.risk)}`
      );
    }


    // ========================================================
    // SORT BY CODE
    // ========================================================

    // ========================================================
    // OUTPUT
    // ========================================================

    const output = {

      lastUpdated:
        new Date().toISOString(),

      mapDate:
        mapDate,

      sourceUrl:
        latest.href,

      imageUrl:
        imageUrl,

      imageSize: {

        width:
          image.bitmap.width,

        height:
          image.bitmap.height

      },

      forestServiceCount:
        Object.keys(forestServices).length,

      forest_services:
        forestServices,

      forest_service_details:
        forestServiceDetails

    };


    // ========================================================
    // SAVE CURRENT
    // ========================================================

    fs.writeFileSync(
      'fire_risk.json',
      JSON.stringify(
        output,
        null,
        2
      ),
      'utf8'
    );


    console.log('');
    console.log(
      '✅ fire_risk.json ενημερώθηκε.'
    );


    // ========================================================
    // SAVE HISTORY
    // ========================================================

    const historyDir =
      './history';


    if (
      !fs.existsSync(
        historyDir
      )
    ) {

      fs.mkdirSync(
        historyDir,
        {
          recursive: true
        }
      );

    }


    const historyFile =
      `${historyDir}/${mapDate}.json`;


    if (
      fs.existsSync(
        historyFile
      )
    ) {

      console.log(
        `ℹ️ Υπάρχει ήδη: ${historyFile}`
      );

      console.log(
        'Το παλιό ιστορικό ΔΕΝ αντικαταστάθηκε.'
      );

    } else {

      fs.writeFileSync(
        historyFile,
        JSON.stringify(
          output,
          null,
          2
        ),
        'utf8'
      );


      console.log(
        `📚 Ιστορικό αποθηκεύτηκε: ` +
        `${historyFile}`
      );

    }


    // ========================================================
    // SUMMARY
    // ========================================================

    console.log('');
    console.log(
      '=============================================='
    );

    console.log(
      `✅ ${Object.keys(forestServices).length} Δ.Υ.`
    );

    console.log(
      `📅 ${mapDate}`
    );

    console.log(
      '=============================================='
    );

  }

  catch (error) {

    console.error('');
    console.error(
      '❌ ERROR:'
    );

    console.error(
      error.message
    );

    process.exitCode = 1;

  }

  finally {

    await browser.close();

  }

}


scrape();