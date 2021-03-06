require 'spec_helper'

describe Gitlab::GithubImport::Importer, lib: true do
  shared_examples 'Gitlab::GithubImport::Importer#execute' do
    let(:expected_not_called) { [] }

    before do
      allow(project).to receive(:import_data).and_return(double.as_null_object)
    end

    it 'calls import methods' do
      importer = described_class.new(project)

      expected_called = [
        :import_labels, :import_milestones, :import_pull_requests, :import_issues,
        :import_wiki, :import_releases, :handle_errors
      ]

      expected_called -= expected_not_called

      aggregate_failures do
        expected_called.each do |method_name|
          expect(importer).to receive(method_name)
        end

        expect(importer).to receive(:import_comments).with(:issues)
        expect(importer).to receive(:import_comments).with(:pull_requests)

        expected_not_called.each do |method_name|
          expect(importer).not_to receive(method_name)
        end
      end

      importer.execute
    end
  end

  shared_examples 'Gitlab::GithubImport::Importer#execute an error occurs' do
    before do
      allow(project).to receive(:import_data).and_return(double.as_null_object)

      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      allow_any_instance_of(Octokit::Client).to receive(:rate_limit!).and_raise(Octokit::NotFound)
      allow_any_instance_of(Gitlab::Shell).to receive(:import_repository).and_raise(Gitlab::Shell::Error)

      allow_any_instance_of(Octokit::Client).to receive(:labels).and_return([label1, label2])
      allow_any_instance_of(Octokit::Client).to receive(:milestones).and_return([milestone, milestone])
      allow_any_instance_of(Octokit::Client).to receive(:issues).and_return([issue1, issue2])
      allow_any_instance_of(Octokit::Client).to receive(:pull_requests).and_return([pull_request, pull_request])
      allow_any_instance_of(Octokit::Client).to receive(:issues_comments).and_return([])
      allow_any_instance_of(Octokit::Client).to receive(:pull_requests_comments).and_return([])
      allow_any_instance_of(Octokit::Client).to receive(:last_response).and_return(double(rels: { next: nil }))
      allow_any_instance_of(Octokit::Client).to receive(:releases).and_return([release1, release2])
    end
    let(:octocat) { double(id: 123456, login: 'octocat') }
    let(:created_at) { DateTime.strptime('2011-01-26T19:01:12Z') }
    let(:updated_at) { DateTime.strptime('2011-01-27T19:01:12Z') }
    let(:label1) do
      double(
        name: 'Bug',
        color: 'ff0000',
        url: "#{api_root}/repos/octocat/Hello-World/labels/bug"
      )
    end

    let(:label2) do
      double(
        name: nil,
        color: 'ff0000',
        url: "#{api_root}/repos/octocat/Hello-World/labels/bug"
      )
    end

    let(:milestone) do
      double(
        id: 1347, # For Gitea
        number: 1347,
        state: 'open',
        title: '1.0',
        description: 'Version 1.0',
        due_on: nil,
        created_at: created_at,
        updated_at: updated_at,
        closed_at: nil,
        url: "#{api_root}/repos/octocat/Hello-World/milestones/1"
      )
    end

    let(:issue1) do
      double(
        number: 1347,
        milestone: nil,
        state: 'open',
        title: 'Found a bug',
        body: "I'm having a problem with this.",
        assignee: nil,
        user: octocat,
        comments: 0,
        pull_request: nil,
        created_at: created_at,
        updated_at: updated_at,
        closed_at: nil,
        url: "#{api_root}/repos/octocat/Hello-World/issues/1347",
        labels: [double(name: 'Label #1')]
      )
    end

    let(:issue2) do
      double(
        number: 1348,
        milestone: nil,
        state: 'open',
        title: nil,
        body: "I'm having a problem with this.",
        assignee: nil,
        user: octocat,
        comments: 0,
        pull_request: nil,
        created_at: created_at,
        updated_at: updated_at,
        closed_at: nil,
        url: "#{api_root}/repos/octocat/Hello-World/issues/1348",
        labels: [double(name: 'Label #2')]
      )
    end

    let(:repository) { double(id: 1, fork: false) }
    let(:source_sha) { create(:commit, project: project).id }
    let(:source_branch) { double(ref: 'feature', repo: repository, sha: source_sha) }
    let(:target_sha) { create(:commit, project: project, git_commit: RepoHelpers.another_sample_commit).id }
    let(:target_branch) { double(ref: 'master', repo: repository, sha: target_sha) }
    let(:pull_request) do
      double(
        number: 1347,
        milestone: nil,
        state: 'open',
        title: 'New feature',
        body: 'Please pull these awesome changes',
        head: source_branch,
        base: target_branch,
        assignee: nil,
        user: octocat,
        created_at: created_at,
        updated_at: updated_at,
        closed_at: nil,
        merged_at: nil,
        url: "#{api_root}/repos/octocat/Hello-World/pulls/1347",
        labels: [double(name: 'Label #2')]
      )
    end

    let(:release1) do
      double(
        tag_name: 'v1.0.0',
        name: 'First release',
        body: 'Release v1.0.0',
        draft: false,
        created_at: created_at,
        updated_at: updated_at,
        url: "#{api_root}/repos/octocat/Hello-World/releases/1"
      )
    end

    let(:release2) do
      double(
        tag_name: 'v2.0.0',
        name: 'Second release',
        body: nil,
        draft: false,
        created_at: created_at,
        updated_at: updated_at,
        url: "#{api_root}/repos/octocat/Hello-World/releases/2"
      )
    end

    it 'returns true' do
      expect(described_class.new(project).execute).to eq true
    end

    it 'does not raise an error' do
      expect { described_class.new(project).execute }.not_to raise_error
    end

    it 'stores error messages' do
      error = {
        message: 'The remote data could not be fully imported.',
        errors: [
          { type: :label, url: "#{api_root}/repos/octocat/Hello-World/labels/bug", errors: "Validation failed: Title can't be blank, Title is invalid" },
          { type: :issue, url: "#{api_root}/repos/octocat/Hello-World/issues/1348", errors: "Validation failed: Title can't be blank" },
          { type: :wiki, errors: "Gitlab::Shell::Error" }
        ]
      }

      unless project.gitea_import?
        error[:errors] << { type: :release, url: "#{api_root}/repos/octocat/Hello-World/releases/2", errors: "Validation failed: Description can't be blank" }
      end

      described_class.new(project).execute

      expect(project.import_error).to eq error.to_json
    end
  end

  let(:project) { create(:project, import_url: "#{repo_root}/octocat/Hello-World.git", wiki_access_level: ProjectFeature::DISABLED) }
  let(:credentials) { { user: 'joe' } }

  context 'when importing a GitHub project' do
    let(:api_root) { 'https://api.github.com' }
    let(:repo_root) { 'https://github.com' }

    it_behaves_like 'Gitlab::GithubImport::Importer#execute'
    it_behaves_like 'Gitlab::GithubImport::Importer#execute an error occurs'

    describe '#client' do
      it 'instantiates a Client' do
        allow(project).to receive(:import_data).and_return(double(credentials: credentials))
        expect(Gitlab::GithubImport::Client).to receive(:new).with(
          credentials[:user],
          {}
        )

        described_class.new(project).client
      end
    end
  end

  context 'when importing a Gitea project' do
    let(:api_root) { 'https://try.gitea.io/api/v1' }
    let(:repo_root) { 'https://try.gitea.io' }
    before do
      project.update(import_type: 'gitea', import_url: "#{repo_root}/foo/group/project.git")
    end

    it_behaves_like 'Gitlab::GithubImport::Importer#execute' do
      let(:expected_not_called) { [:import_releases] }
    end
    it_behaves_like 'Gitlab::GithubImport::Importer#execute an error occurs'

    describe '#client' do
      it 'instantiates a Client' do
        allow(project).to receive(:import_data).and_return(double(credentials: credentials))
        expect(Gitlab::GithubImport::Client).to receive(:new).with(
          credentials[:user],
          { host: "#{repo_root}:443/foo", api_version: 'v1' }
        )

        described_class.new(project).client
      end
    end
  end
end
