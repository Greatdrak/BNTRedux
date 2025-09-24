# Quantum Nova Traders 🚀

A modern space trading game built with Next.js and Supabase. Explore the cosmos, trade resources, build your empire, and conquer the stars in this multiplayer space adventure.

*Inspired by the classic Blacknova Traders game*

## 🌟 Features

- **Multi-Universe Support** - Play across different game universes
- **Real-time Trading** - Dynamic market prices and resource trading
- **Ship Management** - Upgrade ships, manage cargo capacity, and navigate sectors
- **Planet Colonization** - Claim planets, build bases, and manage production
- **Combat System** - Engage in ship-to-ship combat with strategic depth
- **AI Players** - Advanced AI opponents for single-player and multiplayer experiences
- **Leaderboards** - Track your progress and compete with other players
- **Admin Panel** - Comprehensive universe management tools

## 🛠️ Tech Stack

### Frontend
- **Next.js 14** - React framework with App Router
- **React 18** - UI library
- **TypeScript 5** - Type-safe development
- **CSS Modules** - Scoped styling

### Backend & Database
- **Supabase** - Backend-as-a-Service
- **PostgreSQL** - Database
- **Supabase Auth** - Authentication

### Data & State Management
- **SWR** - Data fetching and caching
- **Fetch API** - HTTP client

### Development & Deployment
- **Node.js** - Runtime environment
- **Vercel** - Deployment platform
- **node-cron** - Scheduled tasks

## 🚀 Getting Started

### Prerequisites
- Node.js 18+ 
- npm or yarn
- Supabase account

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd QuantumNovaTraders
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env.local
   ```
   
   Add your Supabase credentials:
   ```env
   NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
   ```

4. **Run database migrations**
   ```bash
   # Apply SQL migrations in order
   # See sql/ directory for migration files
   ```

5. **Start the development server**
   ```bash
   npm run dev
   ```

6. **Open your browser**
   Navigate to [http://localhost:3000](http://localhost:3000)

## 📁 Project Structure

```
QuantumNovaTraders/
├── app/                    # Next.js App Router
│   ├── api/               # API routes
│   ├── game/              # Game interface
│   ├── admin/              # Admin panel
│   └── login/              # Authentication
├── lib/                    # Utility libraries
├── sql/                    # Database migrations
├── scripts/                # Development scripts
├── public/                 # Static assets
└── docs/                   # Documentation
```

## 🎮 Gameplay

### Getting Started
1. **Create Account** - Sign up with email/password
2. **Choose Universe** - Select from available game universes
3. **Create Character** - Choose your player handle
4. **Start Trading** - Begin your space trading journey

### Core Mechanics
- **Movement** - Navigate between sectors using warp gates
- **Trading** - Buy low, sell high across different ports
- **Ship Upgrades** - Improve cargo capacity and ship performance
- **Planet Management** - Claim planets and manage production
- **Combat** - Engage enemies with tactical ship combat

## 🔧 Development

### Available Scripts
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm run lint         # Run ESLint
npm run cron         # Run local cron jobs
npm run cron:test    # Test cron functionality
```

### Database Management
- SQL migrations are located in the `sql/` directory
- Apply migrations in numerical order
- Use `sql_archive/` for historical reference

### Cron Jobs
The game uses scheduled tasks for:
- Turn generation (every 3 minutes)
- Event cycling (every 6 hours)
- Event updates (every 15 minutes)

## 📚 Documentation

- [API Documentation](docs/API_INDEX.md)
- [Admin Guide](docs/ADMIN.md)
- [Trading System](docs/TRADING.md)
- [Movement System](docs/MOVEMENT.md)
- [Mine System](docs/MINES.md)
- [Scheduler](docs/SCHEDULER.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎯 Roadmap

- [ ] Enhanced combat system
- [ ] Guild/Alliance features
- [ ] Mobile app
- [ ] Advanced AI behaviors
- [ ] Tournament system
- [ ] Mod support

## 🏛️ Heritage & Inspiration

**Quantum Nova Traders** is a modern reimagining of the classic **Blacknova Traders** game. We pay homage to the original web-based space trading game that captivated players in the early days of browser gaming.

### About Blacknova Traders
Blacknova Traders was one of the pioneering browser-based multiplayer games, featuring:
- Real-time space trading
- Multiplayer competition
- Strategic resource management
- Turn-based gameplay

### Our Modern Take
While inspired by the original, Quantum Nova Traders brings the classic gameplay into the modern era with:
- **Modern Tech Stack** - Built with Next.js, React, and Supabase
- **Enhanced UI/UX** - Beautiful, responsive interface
- **Real-time Updates** - Live game state synchronization
- **Advanced Features** - Combat system, planet management, AI players
- **Mobile Ready** - Responsive design for all devices

We're grateful to the original Blacknova Traders community and developers for creating such an engaging game that continues to inspire new generations of space trading games.

## 🆘 Support

- **Issues** - Report bugs and request features on GitHub
- **Discord** - Join our community server
- **Email** - Contact the development team

---

**Quantum Nova Traders** - Where the stars are your playground! 🌌

*Inspired by the legendary Blacknova Traders*