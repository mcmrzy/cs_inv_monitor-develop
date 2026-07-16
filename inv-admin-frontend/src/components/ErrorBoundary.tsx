import React from 'react';
import { Button, Result } from 'antd';
import locales from '@/locales';
import useLocaleStore from '@/stores/localeStore';

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('[ErrorBoundary]', error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
    window.location.href = '/login';
  };

  render() {
    if (this.state.hasError) {
      const dictionary = locales[useLocaleStore.getState().lang];
      const t = (key: string) => dictionary[key] ?? key;
      return (
        <div style={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#f0f2f5',
        }}>
          <Result
            status="error"
            title={t('error.pageTitle')}
            subTitle={this.state.error?.message || t('error.unknown')}
            extra={[
              <Button type="primary" key="retry" onClick={this.handleReset}>
                {t('error.backToLogin')}
              </Button>,
              <Button key="detail" onClick={() => alert(JSON.stringify({
                message: this.state.error?.message,
                stack: this.state.error?.stack,
              }))}>
                {t('error.viewDetails')}
              </Button>,
            ]}
          />
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
