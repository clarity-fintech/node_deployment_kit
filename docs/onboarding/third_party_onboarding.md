# Third-Party Onboarding

## Institutional pipeline (9 stages)

Run `clrty institutional <stage_index>` where stages are:

1. intake
2. kyc
3. custody
4. routing
5. settlement
6. reporting
7. audit
8. compliance
9. finalize

## API access

Use `clrty remote ping <host>` to verify connectivity before enabling producer mode on the FMA relayer.

## Settlement (stage 5)

See [Programmable Settlement Gatekeeper](../investor/settlement_gatekeeper.md) for Safe-monitored register binding after KYC attestation.

## B2B scheduling (Calendly)

Tasks requiring partner meetings (legal counsel, genesis ceremony, CEX listing) are tracked in Notion with a **Schedule** URL. Embed inline booking on checkout:

```html
<script src="https://assets.calendly.com/assets/external/widget.js"></script>
<div id="calendly-embed" style="min-width:320px;height:580px;"></div>
<script>
  Calendly.initInlineWidget({
    url: 'https://calendly.com/YOUR-B2B-LINK',
    parentElement: document.getElementById('calendly-embed'),
    prefill: {},
    utm: { utmCampaign: 'clrty-b2b' }
  });
</script>
```

Set `CALENDLY_EMBED_URL` in `.env`. See [NOTION_LAUNCH_TRACKER_SETUP.md](../monetization/NOTION_LAUNCH_TRACKER_SETUP.md).
