import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initializeApp, cert, getApps } from "npm:firebase-admin/app";
import { getMessaging } from "npm:firebase-admin/messaging";

// 1. Ρύθμιση του Firebase Admin (Διαβάζει το μυστικό αρχείο που βάλαμε στο Supabase)
const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
if (serviceAccountStr && !getApps().length) {
  const serviceAccount = JSON.parse(serviceAccountStr);
  initializeApp({
    credential: cert(serviceAccount),
  });
}

serve(async (req) => {
  try {
    // 2. Διαβάζουμε τα δεδομένα που έστειλε η βάση (Webhook Payload)
    const payload = await req.json();

    // 3. Ελέγχουμε αν η αλλαγή είναι ΕΝΕΡΓΟΠΟΙΗΣΗ ΣΥΝΑΓΕΡΜΟΥ (UPDATE -> is_theft_alert_triggered = true)
    if (payload.type === "UPDATE" && payload.record.is_theft_alert_triggered === true) {
      const ownerId = payload.record.owner_id;
      const hiveName = payload.record.hive_name || "Άγνωστη Κυψέλη";

      if (!ownerId) {
        return new Response("Δεν βρέθηκε ιδιοκτήτης", { status: 200 });
      }

      // 4. Συνδεόμαστε στο Supabase για να βρούμε το Token του κινητού του ιδιοκτήτη
      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
      );

      const { data: userToken, error } = await supabaseAdmin
        .from("user_tokens")
        .select("token")
        .eq("user_id", ownerId)
        .single();

      if (error || !userToken) {
        console.log("Δεν βρέθηκε FCM Token για τον χρήστη:", ownerId);
        return new Response("Ο χρήστης δεν έχει Token", { status: 200 });
      }

      // 5. Φτιάχνουμε και στέλνουμε το Push Notification στο κινητό!
      const message = {
        notification: {
          title: "🚨 ΣΥΝΑΓΕΡΜΟΣ ΚΛΟΠΗΣ!",
          body: `Ανιχνεύθηκε παραβίαση στην: ${hiveName}. Ανοίξτε την εφαρμογή άμεσα!`,
        },
        token: userToken.token,
      };

      const response = await getMessaging().send(message);
      console.log("✅ Η ειδοποίηση στάλθηκε επιτυχώς:", response);
    }

    return new Response("Επιτυχία", { status: 200 });
  } catch (error) {
    console.error("Σφάλμα:", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});