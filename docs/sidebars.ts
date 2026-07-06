import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {type: 'doc', id: 'index', label: 'Documentation Guide'},
    {type: 'doc', id: 'README', label: 'Overview'},
    {
      type: 'category',
      label: 'Start Here',
      collapsed: false,
      items: [
        {type: 'doc', id: 'migrating-heroku-to-control-plane', label: 'Migrate from Heroku'},
        {type: 'doc', id: 'ci-automation', label: 'Automate GitHub Flow'},
        {type: 'doc', id: 'ai-github-flow-prompt', label: 'AI Rollout Prompt'},
        {type: 'doc', id: 'commands', label: 'Command Reference'},
      ],
    },
    {
      type: 'category',
      label: 'Core Operations',
      items: [
        'secrets-and-env-values',
        'dns',
        'thruster',
        'troubleshooting',
        'tips',
      ],
    },
    {
      type: 'category',
      label: 'Telemetry',
      link: {type: 'doc', id: 'telemetry/index'},
      items: [
        'telemetry/collector',
        'telemetry/application-instrumentation',
        'telemetry/pipelines',
        'telemetry/review-apps',
        'telemetry/troubleshooting',
      ],
    },
    {
      type: 'category',
      label: 'Data Services',
      items: [
        'postgres',
        'redis',
      ],
    },
    {
      type: 'category',
      label: 'Terraform',
      items: [
        'terraform/overview',
        'terraform/details',
      ],
    },
    {
      type: 'category',
      label: 'Project',
      items: [
        {type: 'doc', id: 'releasing', label: 'Releasing the Gem'},
        {type: 'doc', id: 'changelog', label: 'Changelog'},
      ],
    },
  ],
};

export default sidebars;
