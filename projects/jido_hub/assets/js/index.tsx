import React, { useEffect } from "react";
import { createRoot } from "react-dom/client";

// Declare Prism for TypeScript
declare global {
  interface Window {
    Prism: any;
  }
}

const AshTypescriptGuide = () => {
  useEffect(() => {
    // Trigger Prism highlighting after component mounts
    if (window.Prism) {
      window.Prism.highlightAll();
    }
  }, []);

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-orange-50">
      <div className="max-w-4xl mx-auto p-8">
        <div className="flex items-center gap-6 mb-12">
          <img
            src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
            alt="AshTypescript Logo"
            className="w-20 h-20"
          />
          <div>
            <h1 className="text-5xl font-bold text-slate-900 mb-2">
              AshTypescript
            </h1>
            <p className="text-xl text-slate-600 font-medium">
              Type-safe TypeScript bindings for Ash Framework
            </p>
          </div>
        </div>

        <div className="space-y-12">
          <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                1
              </div>
              <h2 className="text-2xl font-bold text-slate-900">
                Configure RPC in Your Domain
              </h2>
            </div>
            <p className="text-slate-700 mb-6 text-lg leading-relaxed">
              Add the AshTypescript.Rpc extension to your domain and configure RPC actions:
            </p>
            <pre className="rounded-lg overflow-x-auto text-sm border">
              <code className="language-elixir">
{`defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Accounts.User do
      rpc_action :get_by_email, :get_by_email
      rpc_action :list_users, :read
      rpc_action :get_user, :read
    end
  end

  resources do
    resource MyApp.Accounts.User
  end
end`}
              </code>
            </pre>
          </section>

          <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                2
              </div>
              <h2 className="text-2xl font-bold text-slate-900">
                TypeScript Auto-Generation
              </h2>
            </div>
            <p className="text-slate-700 mb-6 text-lg leading-relaxed">
              When running the dev server, TypeScript types are automatically generated for you:
            </p>
            <pre className="rounded-lg text-sm border mb-6">
              <code className="language-bash">mix phx.server</code>
            </pre>
            <div className="bg-orange-50 border border-orange-200 rounded-lg p-6 mb-6">
              <p className="text-slate-700 text-lg leading-relaxed">
                <strong className="text-orange-700">✨ Automatic regeneration:</strong> TypeScript files are automatically regenerated whenever you make changes to your resources or expose new RPC actions. No manual codegen step required during development!
              </p>
            </div>
            <p className="text-slate-600 mb-4">
              For production builds or manual generation, you can also run:
            </p>
            <pre className="rounded-lg text-sm border">
              <code className="language-bash">mix ash_typescript.codegen --output "assets/js/ash_generated.ts"</code>
            </pre>
          </section>

          <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                3
              </div>
              <h2 className="text-2xl font-bold text-slate-900">
                Import and Use Generated Functions
              </h2>
            </div>
            <p className="text-slate-700 mb-6 text-lg leading-relaxed">
              Import the generated RPC functions in your TypeScript/React code:
            </p>
            <pre className="rounded-lg overflow-x-auto text-sm border">
              <code className="language-typescript">
{`import { getByEmail, listUsers, getUser } from "./ash_generated";

// Use the typed RPC functions
const findUserByEmail = async (email: string) => {
  try {
    const result = await getByEmail({ email });
    if (result.success) {
      console.log("User found:", result.data);
      return result.data;
    } else {
      console.error("User not found:", result.errors);
      return null;
    }
  } catch (error) {
    console.error("Network error:", error);
    return null;
  }
};

const fetchUsers = async () => {
  try {
    const result = await listUsers();
    if (result.success) {
      console.log("Users:", result.data);
    } else {
      console.error("Failed to fetch users:", result.errors);
    }
  } catch (error) {
    console.error("Network error:", error);
  }
};`}
              </code>
            </pre>
          </section>

          <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
            <h2 className="text-2xl font-bold text-slate-900 mb-8">
              Learn More & Examples
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <a
                href="https://hexdocs.pm/ash_typescript"
                target="_blank"
                rel="noopener noreferrer"
                className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
              >
                <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                  <span className="text-orange-600 font-bold text-xl">📚</span>
                </div>
                <div>
                  <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Documentation</h3>
                  <p className="text-slate-600">Complete API reference and guides on HexDocs</p>
                </div>
              </a>

              <a
                href="https://github.com/ash-project/ash_typescript"
                target="_blank"
                rel="noopener noreferrer"
                className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
              >
                <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                  <span className="text-orange-600 font-bold text-xl">🔧</span>
                </div>
                <div>
                  <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Source Code</h3>
                  <p className="text-slate-600">View the source, report issues, and contribute on GitHub</p>
                </div>
              </a>

              <a
                href="https://github.com/ChristianAlexander/ash_typescript_demo"
                target="_blank"
                rel="noopener noreferrer"
                className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
              >
                <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                  <span className="text-orange-600 font-bold text-xl">🚀</span>
                </div>
                <div>
                  <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Demo App</h3>
                  <p className="text-slate-600">See AshTypescript with TanStack Query & Table in action</p>
                  <p className="text-slate-500 text-sm mt-1">by ChristianAlexander</p>
                </div>
              </a>
            </div>
          </section>

          <div className="bg-gradient-to-r from-orange-500 to-orange-600 rounded-xl shadow-lg p-8 text-center">
            <div className="flex items-center justify-center mb-4">
              <div className="w-12 h-12 bg-white rounded-full flex items-center justify-center">
                <span className="text-orange-600 font-bold text-xl">🚀</span>
              </div>
            </div>
            <h3 className="text-2xl font-bold text-white mb-3">
              Ready to Get Started?
            </h3>
            <p className="text-orange-100 text-lg leading-relaxed max-w-2xl mx-auto">
              Check your generated RPC functions and start building type-safe interactions between your frontend and Ash resources!
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

const root = createRoot(document.getElementById("app")!);

root.render(
  <React.StrictMode>
    <AshTypescriptGuide />
  </React.StrictMode>,
);
