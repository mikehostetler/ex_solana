# Docket Hauler - Migration Project Guide

## Project Overview

**Docket Hauler** is undergoing a complete modernization from React-Boilerplate to Vite + React 18 + TypeScript 5. This project involves porting a logistics/hauling management application while preserving 100% business functionality.

**Current State**: 
- `docket-hauler/` - Legacy React-Boilerplate application (v0.5.0)
- `new-docket-hauler/` - Target Vite+React+TypeScript application (empty, to be created)
- `specs/` - Complete technical specifications for the migration

## Quick Start Commands

### Legacy Application (docket-hauler/)
```bash
cd docket-hauler
npm start                 # Start development server on https://localhost:4443
npm run start:tunnel      # Start with ngrok tunneling for remote testing
npm test                  # Run Jest unit tests with 98% coverage requirement
npm run build            # Build for production
npm run deploy          # Build and deploy to Firebase
```

### New Application (new-docket-hauler/)
```bash
cd new-docket-hauler
npm run dev         # Start development server on https://localhost:4444
npm run build       # TypeScript + Vite production build
npm test           # Jest test suite (148 tests)
npm run lint       # ESLint + Prettier
```

### Development Tools
```bash
npm run lint             # ESLint + Prettier
npm run generate         # Plop component generator (legacy)
npm run analyze          # Bundle size analysis
```

## Project Structure

### Legacy (docket-hauler/)
```
docket-hauler/
├── app/                     # React application
│   ├── components/          # 40+ reusable UI components
│   ├── containers/          # Redux-connected smart components
│   │   ├── App/            # Root app with routing
│   │   ├── Dashboard/      # Main hauler dashboard
│   │   ├── FindDashboard/  # Authentication/login
│   │   └── AcceptPage/     # Task acceptance workflow
│   ├── utils/              # Helper functions
│   ├── constants/          # API endpoints, routes
│   ├── helpers/            # Business logic
│   ├── firebaseConfig/     # Firebase/Firestore config
│   └── translations/       # i18n files
├── server/                 # Express.js HTTPS server
└── internals/              # Build tools, webpack config
```

### Target (new-docket-hauler/)
```
src/
├── app/                # Feature slices
│   ├── auth/
│   ├── dashboard/
│   ├── tasks/
│   ├── files/
│   └── messaging/
├── components/         # Reusable UI library (Flex*, widgets)
├── api/                # Firebase wrappers & RTK Query endpoints
├── hooks/              # Custom hooks (useAuth, useFirestoreQuery)
├── routes/             # Route objects + lazy pages
├── theme/              # ThemeController, CSS vars
├── utils/              # Pure helpers
└── index.tsx           # SPA bootstrap
```

## Technology Stack Migration

### From (Legacy)
- **React 16.13.1** with class components
- **Webpack 4** with complex config
- **Redux + Redux-Saga** with connect()
- **Babel** transpilation
- **Material-UI 4.x**
- **Moment.js** for dates
- **Immutable.js** for state

### To (Target)
- **React 18** with functional components + hooks
- **Vite** for <50ms cold start & <20ms HMR
- **Redux Toolkit + RTK Query** with useSelector/useDispatch
- **TypeScript 5** strict mode
- **Semantic-UI-React** (retained)
- **Luxon** for dates
- **Immer** (built into RTK) for immutability

## Key Specifications

### Core Features (Preserved)
- **Task Management**: Accept, decline, complete hauling tasks
- **Real-time Updates**: Firebase/Firestore synchronization
- **File Handling**: Drag-drop uploads, attachments, file viewer
- **Authentication**: Email/PIN login system
- **Mobile-first Design**: Touch-friendly responsive interface
- **Company Theming**: Dynamic color schemes

### Architecture Patterns
- **Feature Slices**: Group by functionality (auth/, dashboard/, tasks/)
- **Container/Component**: Smart containers + dumb components (legacy pattern preserved)
- **Redux Toolkit**: createSlice() instead of legacy reducers
- **TypeScript**: Strict typing throughout

### Architecture Decisions
- Feature-slice organization (auth/, dashboard/, tasks/)
- Redux Toolkit for state management
- Firebase v9 for real-time data
- React Router v6 for modern routing
- Luxon for date handling (replacing Moment.js)

### Key Development Learnings
- Vite provides <50ms cold start vs Webpack's slower builds
- Firebase v9 modular SDK requires different import patterns
- Redux Toolkit reduces boilerplate by ~70% vs legacy Redux
- TypeScript strict mode caught many potential runtime errors
- Jest + @testing-library/react works well with Firebase mocking
- React 18 functional components + hooks vs legacy class components

## Migration Implementation Order

1. **Tooling Setup** (Vite, TS, ESLint, Prettier, Jest)
2. **Core Layout** (folder structure, ThemeController)
3. **Routing Skeleton** (React Router v6)
4. **Auth Slice** (unblocks protected routes)
5. **Global State** (Redux store + RTK scaffolding)
6. **Dashboard Slice** (Firestore listeners)
7. **Task Workflows** (accept/decline/complete)
8. **File System** (Storage utilities)
9. **Real-time Features** (notifications)
10. **PWA/Offline** (Vite-PWA plugin)

## Development Workflow

### Code Style Standards
- **ESLint**: Airbnb configuration + React hooks
- **Prettier**: 2-space indentation, single quotes, trailing commas
- **File Naming**: PascalCase for components, camelCase for utilities
- **Import Order**: External libraries, then internal modules

### Testing Strategy
- **Jest 29** + @testing-library/react
- **98% Coverage Requirement** (maintained from legacy)
- **Component Testing**: Snapshot + behavior tests
- **Firebase Mocking**: @firebase/rules-unit-testing

### Testing Approach (Implemented)
- 148 tests passing with 98% coverage maintained
- Firebase services mocked for unit tests
- Redux state management fully tested
- Component integration tests with routing

### State Management Patterns
```typescript
// Legacy Pattern
connect(mapStateToProps, mapDispatchToProps)(Component)

// New Pattern
const data = useSelector(selectData);
const dispatch = useDispatch();
```

## Firebase Integration

### Database Structure (Preserved)
- **Firestore**: Companies, haulers, tasks, job data
- **Authentication**: Email/PIN combination
- **Storage**: File attachments and documents
- **Hosting**: Production deployment target

### API Migration
```javascript
// Legacy (v8 SDK)
import firebase from 'firebase/app';
import 'firebase/firestore';

// Target (v9 modular SDK)
import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
```

## Common Issues & Solutions

### Development Environment
- **HTTPS Required**: Legacy runs on port 4443 with SSL
- **Firebase Config**: Separate .env files for dev/prod
- **Hot Reloading**: Vite provides superior HMR compared to Webpack

### Build & Deployment
- **Memory Issues**: Vite is more efficient than Webpack
- **Bundle Size**: Monitor with `npm run analyze`
- **Firebase Deployment**: Same process, just different build output

## Testing & Quality Assurance

### Coverage Requirements
- **Statements**: 98%
- **Branches**: 91%
- **Functions**: 98%
- **Lines**: 98%

### Test Commands
```bash
npm test                 # Run all tests
npm run test:watch       # Watch mode for development
npm run test:coverage    # Generate coverage report
```

## File Organization Patterns

### Component Migration Pattern
```typescript
// Legacy Class Component
class TaskCard extends Component {
  componentDidMount() { /* ... */ }
  render() { /* ... */ }
}

// Target Functional Component
const TaskCard: React.FC<TaskCardProps> = ({ task }) => {
  useEffect(() => { /* ... */ }, []);
  return /* ... */;
};
```

### State Migration Pattern
```typescript
// Legacy Redux
const mapStateToProps = state => ({
  tasks: state.get('dashboard').get('tasks')
});

// Target RTK
const tasks = useSelector((state: RootState) => state.dashboard.tasks);
```

## Debugging & Monitoring

### Development Tools
- **Redux DevTools**: Monitor state changes
- **React DevTools**: Component hierarchy inspection
- **Vite DevTools**: Build analysis and HMR debugging
- **Firebase Emulator**: Local development environment

### Performance Monitoring
- **Bundle Analysis**: `npm run analyze`
- **Core Web Vitals**: Monitor real-world performance
- **Firebase Analytics**: User interaction tracking

## Key Migration Checkpoints

1. **Functionality Parity**: All existing features work identically
2. **Performance Improvement**: <50ms cold start, <20ms HMR
3. **Type Safety**: Full TypeScript coverage with strict mode
4. **Test Coverage**: Maintain 98% coverage requirement
5. **Build Optimization**: Smaller bundle size than legacy
6. **Developer Experience**: Faster build/test cycles

## Resources & Documentation

- **Specifications**: `/specs/` folder contains complete technical specs
- **Migration Guide**: `/specs/migration-guide.md` - step-by-step process
- **Architecture**: `/specs/architecture.md` - system design
- **Legacy Documentation**: `/docket-hauler/docs/` - React Boilerplate docs

---

*Last Updated: July 2025*
*Migration Status: Core Migration Complete (v0.1.0)*

## Migration Status

- **Core functionality**: ✅ Complete
- **Authentication**: ✅ Complete
- **Task management**: ✅ Complete
- **Real-time updates**: ✅ Complete
- **Build system**: ✅ Complete
