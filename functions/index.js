const { onValueCreated, onValueWritten } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * 1. INCOMING CALL PUSH TRIGGER
 * Triggers when a new call session is written to /calls/{targetId}
 */
exports.onCallCreated = onValueWritten({
  ref: "/calls/{targetId}",
  region: "europe-west1"
}, async (event) => {
  const callData = event.data.after.val();
  if (!callData) return;

  const status = callData.status;
  const targetId = event.params.targetId;
  const pin = targetId.split("_").pop();

  // If call ended/cancelled, send cancel push to stop ringing UI
  if (status === "ended" || status === "rejected") {
    return _sendCancelPushToTarget(targetId, pin, callData.callId);
  }

  // Only trigger on active calling state
  if (status !== "calling") return;

  console.log(`📞 [CALL PUSH TRIGGER] Target: ${targetId}, Caller: ${callData.callerName} (${callData.callId})`);

  const fcmToken = await _getFcmTokenForTarget(targetId, pin);
  if (!fcmToken) {
    console.warn(`⚠️ No FCM token found for target: ${targetId}`);
    return;
  }

  const isVideo = callData.type === "video";
  const callerName = callData.callerName || "Bilinmeyen Arayan";
  const callId = callData.callId || `call_${Date.now()}`;
  const callerId = callData.callerId || "";

  const payload = {
    token: fcmToken,
    notification: {
      title: `Gelen ${isVideo ? "Görüntülü" : "Sesli"} Arama`,
      body: `${callerName} sizi arıyor...`,
    },
    android: {
      priority: "high",
      ttl: 60, // 60 seconds TTL
      notification: {
        channelId: "omega_incoming_calls",
        sound: "default",
        defaultSound: true,
        defaultVibrateTimings: true,
        notificationPriority: "priority_max",
        visibility: "public",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      data: {
        type: "incoming_call",
        callId: callId,
        callerName: callerName,
        callerId: callerId,
        callType: isVideo ? "video" : "audio",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 60),
      },
      payload: {
        aps: {
          alert: {
            title: `Gelen ${isVideo ? "Görüntülü" : "Sesli"} Arama`,
            body: `${callerName} sizi arıyor...`,
          },
          sound: "default",
          badge: 1,
          contentAvailable: true,
          interruptionLevel: "time-sensitive",
        },
        type: "incoming_call",
        callId: callId,
        callerName: callerName,
        callerId: callerId,
        callType: isVideo ? "video" : "audio",
      },
    },
    data: {
      type: "incoming_call",
      callId: callId,
      callerName: callerName,
      callerId: callerId,
      callType: isVideo ? "video" : "audio",
    },
  };

  try {
    const response = await admin.messaging().send(payload);
    console.log(`✅ [CALL PUSH SENT] Message ID: ${response}`);
  } catch (error) {
    console.error(`❌ [CALL PUSH ERROR]:`, error);
  }
});

/**
 * 2. CHAT MESSAGE PUSH TRIGGER
 * Triggers when a new message is sent to /messages/{targetId}/{messageId}
 */
exports.onMessageCreated = onValueCreated({
  ref: "/messages/{targetId}/{messageId}",
  region: "europe-west1"
}, async (event) => {
  const msg = event.data.val();
  if (!msg) return;

  const targetId = event.params.targetId;
  const pin = targetId.split("_").pop();

  console.log(`💬 [MSG PUSH TRIGGER] Target: ${targetId}, Sender: ${msg.senderName}`);

  const fcmToken = await _getFcmTokenForTarget(targetId, pin);
  if (!fcmToken) return;

  const senderName = msg.senderName || "Yeni Mesaj";
  const text = msg.text || "Bir mesaj aldınız";
  const senderId = msg.senderId || "";

  const payload = {
    token: fcmToken,
    notification: {
      title: senderName,
      body: text,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "omega_messages",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      data: {
        type: "new_message",
        senderName: senderName,
        text: text,
        senderId: senderId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: {
            title: senderName,
            body: text,
          },
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
        type: "new_message",
        senderName: senderName,
        text: text,
        senderId: senderId,
      },
    },
    data: {
      type: "new_message",
      senderName: senderName,
      text: text,
      senderId: senderId,
    },
  };

  try {
    await admin.messaging().send(payload);
    console.log(`✅ [MSG PUSH SENT] To ${targetId}`);
  } catch (error) {
    console.error(`❌ [MSG PUSH ERROR]:`, error);
  }
});

/**
 * 3. CAMERA MOTION ALERT PUSH TRIGGER
 * Triggers when a security camera detects motion and writes to /camera_motion_alerts/{pin}
 */
exports.onMotionAlert = onValueWritten({
  ref: "/camera_motion_alerts/{pin}",
  region: "europe-west1"
}, async (event) => {
  const alertData = event.data.after.val();
  if (!alertData) return;

  const pin = event.params.pin;
  console.log(`🚨 [MOTION PUSH TRIGGER] Pin: ${pin}, Camera: ${alertData.cameraDeviceName}`);

  const fcmToken = await _getFcmTokenForTarget(pin, pin);
  if (!fcmToken) return;

  const cameraName = alertData.cameraDeviceName || "Güvenlik Kamerası";

  const payload = {
    token: fcmToken,
    notification: {
      title: "🚨 HAREKET ALGILANDI",
      body: `"${cameraName}" güvenlik kamerasında hareket tespit edildi!`,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "omega_camera_alerts",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      data: {
        type: "motion_alert",
        cameraName: cameraName,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: {
            title: "🚨 HAREKET ALGILANDI",
            body: `"${cameraName}" güvenlik kamerasında hareket tespit edildi!`,
          },
          sound: "default",
          badge: 1,
          contentAvailable: true,
          interruptionLevel: "time-sensitive",
        },
        type: "motion_alert",
        cameraName: cameraName,
      },
    },
    data: {
      type: "motion_alert",
      cameraName: cameraName,
    },
  };

  try {
    await admin.messaging().send(payload);
    console.log(`✅ [MOTION PUSH SENT] To Pin ${pin}`);
  } catch (error) {
    console.error(`❌ [MOTION PUSH ERROR]:`, error);
  }
});

// Helper: Fetch FCM Token from /fcmTokens node
async function _getFcmTokenForTarget(targetId, pin) {
  const targets = [targetId, pin, `omega_tablet_${pin}`, `omega_parent_${pin}`];
  for (const t of targets) {
    try {
      const snap = await admin.database().ref(`/fcmTokens/${t}`).once("value");
      const val = snap.val();
      if (val && val.fcmToken) {
        return val.fcmToken;
      }
    } catch (_) {}
  }
  return null;
}

// Helper: Send cancel call push to stop ringing CallKit UI
async function _sendCancelPushToTarget(targetId, pin, callId) {
  const fcmToken = await _getFcmTokenForTarget(targetId, pin);
  if (!fcmToken) return;

  const payload = {
    token: fcmToken,
    android: {
      priority: "high",
      data: {
        type: "cancel_call",
        callId: callId || "",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: { contentAvailable: true },
        type: "cancel_call",
        callId: callId || "",
      },
    },
    data: {
      type: "cancel_call",
      callId: callId || "",
    },
  };

  try {
    await admin.messaging().send(payload);
    console.log(`🛑 [CANCEL CALL PUSH SENT] To ${targetId}`);
  } catch (_) {}
}
