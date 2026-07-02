import React from 'react';

export interface PanelHeaderProps {
  title: string;
  icon?: React.ReactNode;
  extra?: React.ReactNode;
}

const PanelHeader: React.FC<PanelHeaderProps> = ({ title, icon, extra }) => {
  return (
    <div className="bs-panel-title">
      {icon && <span className="bs-panel-title-icon">{icon}</span>}
      <span>{title}</span>
      {extra && <span className="bs-panel-title-extra">{extra}</span>}
    </div>
  );
};

export default PanelHeader;
