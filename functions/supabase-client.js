// ── Supabase client for the Edge Gateway Dashboard backend ──
// Uses the anon key; RLS policies allow all access since the server
// handles auth via API_KEY at the HTTP layer.
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || "";
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || "";

/** Singleton Supabase client for backend operations. */
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  db: { schema: "public" },
});

// ── Persistence helpers ──────────────────────────────────────────────────────

/**
 * Save an intercept capture to the `intercepted_traffic` table.
 * Returns the inserted row (with server-generated id and created_at).
 */
export async function persistIntercept(capture) {
  const { data, error } = await supabase
    .from("intercepted_traffic")
    .insert({
      slug: capture.slug || "",
      method: capture.method || "GET",
      path: capture.path || "/",
      host: capture.host || "",
      req_headers: capture.reqHeaders || "",
      req_body: capture.reqBody || "",
      resp_status: capture.respStatus || 200,
      resp_headers: capture.respHeaders || "",
      resp_body: capture.respBody || "",
      raw_timestamp: capture.ts || Date.now(),
    })
    .select()
    .single();

  if (error) {
    console.error("[supabase] persistIntercept failed:", error.message);
    return null;
  }
  return data;
}

/**
 * Save AI analysis results for an intercept.
 */
export async function persistAnalysis(interceptId, analysis) {
  const { data, error } = await supabase
    .from("ai_intercept_analysis")
    .insert({
      intercept_id: interceptId,
      category: analysis.category || "uncategorized",
      sensitivity_level: analysis.sensitivityLevel || "none",
      summary: analysis.summary || "",
      extracted_credentials: analysis.extractedCredentials || {},
      tags: analysis.tags || [],
      security_findings: analysis.securityFindings || [],
      model_used: analysis.modelUsed || "",
      tokens_used: analysis.tokensUsed || 0,
    })
    .select()
    .single();

  if (error) {
    console.error("[supabase] persistAnalysis failed:", error.message);
    return null;
  }
  return data;
}

/**
 * Fetch intercepts with optional filtering, pagination, and AI analysis join.
 */
export async function fetchIntercepts({ slug, host, limit = 50, offset = 0, includeAnalysis = false } = {}) {
  let query = supabase
    .from("intercepted_traffic")
    .select(includeAnalysis
      ? "*, ai_intercept_analysis(*)"
      : "*"
    )
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (slug) query = query.eq("slug", slug);
  if (host) query = query.eq("host", host);

  const { data, error, count } = await query;
  if (error) {
    console.error("[supabase] fetchIntercepts failed:", error.message);
    return { data: [], count: 0, error };
  }
  return { data: data || [], count: data?.length || 0 };
}

/**
 * Fetch AI analysis for a specific intercept.
 */
export async function fetchAnalysis(interceptId) {
  const { data, error } = await supabase
    .from("ai_intercept_analysis")
    .select("*")
    .eq("intercept_id", interceptId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  if (error && error.code !== "PGRST116") {
    console.error("[supabase] fetchAnalysis failed:", error.message);
    return null;
  }
  return data;
}

/**
 * Fetch AI-organized intercepts — intercepts joined with their latest analysis,
 * filterable by category, sensitivity, or tags.
 */
export async function fetchOrganizedIntercepts({
  category,
  sensitivityLevel,
  tag,
  limit = 50,
  offset = 0,
} = {}) {
  let query = supabase
    .from("ai_intercept_analysis")
    .select("*, intercepted_traffic!inner(*)")
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (category) query = query.eq("category", category);
  if (sensitivityLevel) query = query.eq("sensitivity_level", sensitivityLevel);
  if (tag) query = query.contains("tags", [tag]);

  const { data, error } = query;
  if (error) {
    console.error("[supabase] fetchOrganizedIntercepts failed:", error.message);
    return { data: [], error };
  }
  return { data: data || [] };
}

/**
 * Get aggregated stats: counts by category, sensitivity, and top tags.
 */
export async function fetchAnalysisStats() {
  const { data, error } = await supabase
    .from("ai_intercept_analysis")
    .select("category, sensitivity_level, tags");

  if (error) {
    console.error("[supabase] fetchAnalysisStats failed:", error.message);
    return null;
  }

  const byCategory = {};
  const bySensitivity = {};
  const tagCounts = {};
  let total = 0;

  for (const row of data || []) {
    total++;
    byCategory[row.category] = (byCategory[row.category] || 0) + 1;
    bySensitivity[row.sensitivity_level] = (bySensitivity[row.sensitivity_level] || 0) + 1;
    for (const t of row.tags || []) {
      tagCounts[t] = (tagCounts[t] || 0) + 1;
    }
  }

  return { total, byCategory, bySensitivity, topTags: tagCounts };
}

/**
 * Delete an intercept and its analysis (cascaded by FK).
 */
export async function deleteIntercept(interceptId) {
  const { error } = await supabase
    .from("intercepted_traffic")
    .delete()
    .eq("id", interceptId);

  if (error) {
    console.error("[supabase] deleteIntercept failed:", error.message);
    return false;
  }
  return true;
}

/**
 * Wipe all intercepts (admin action).
 */
export async function clearAllIntercepts() {
  const { error } = await supabase
    .from("intercepted_traffic")
    .delete()
    .neq("id", 0); // delete all rows

  if (error) {
    console.error("[supabase] clearAllIntercepts failed:", error.message);
    return false;
  }
  return true;
}
