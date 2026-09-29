import Anthropic from '@anthropic-ai/sdk';

// Languages offered in the chat language picker.
export const LANGUAGES = {
  th: 'Thai', en: 'English', zh: 'Simplified Chinese', ja: 'Japanese',
  ko: 'Korean', ru: 'Russian', de: 'German', fr: 'French',
};
export const isLanguage = (l) => Object.hasOwn(LANGUAGES, l);

const MODEL = process.env.TRANSLATE_MODEL ?? 'claude-opus-5';
const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;
export const translationEnabled = () => client !== null;

const SYSTEM = `You translate chat messages in a tour-group app used by a Thai tour guide and international tourists.
Translate naturally and briefly, the way a friendly local guide would say it. Keep emoji, numbers, times, and units.
Keep Thai place names recognisable: give the common English/local name, e.g. "Doi Suthep", "Wat Phra That".
Never add explanations. If the text is already in a target language, return it unchanged for that language.`;

/**
 * Translate one message into several languages in a single request.
 * @returns {Promise<Record<string,string>>} lang code -> text ({} when disabled or on failure)
 */
export async function translate(text, sourceLang, targets) {
  const langs = [...new Set(targets)].filter((l) => l !== sourceLang && isLanguage(l));
  if (!client || langs.length === 0 || !text.trim()) return {};

  const schema = {
    type: 'object',
    properties: Object.fromEntries(langs.map((l) => [l, { type: 'string' }])),
    required: langs,
    additionalProperties: false,
  };
  try {
    const res = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 4000,
      // refused requests are re-run on a fallback model chosen by the API
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      system: SYSTEM,
      messages: [{
        role: 'user',
        content: `Source language: ${LANGUAGES[sourceLang] ?? 'auto-detect'}\n`
          + `Target languages (JSON keys): ${langs.map((l) => `${l} = ${LANGUAGES[l]}`).join(', ')}\n\n<message>\n${text}\n</message>`,
      }],
    });
    if (res.stop_reason !== 'end_turn') return {};
    const block = res.content.find((b) => b.type === 'text');
    const out = JSON.parse(block?.text ?? '{}');
    return Object.fromEntries(Object.entries(out).filter(([l, t]) => langs.includes(l) && typeof t === 'string'));
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) console.warn('translate: rate limited');
    else if (e instanceof Anthropic.APIError) console.error(`translate: API ${e.status}`, e.message);
    else console.error('translate:', e.message);
    return {};
  }
}
